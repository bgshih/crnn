local _ = require 'underscore'
local bit = require 'bit'
local dump = require 'utils'.dump
local ffi = require 'ffi'
local lmdb = require 'lmdb_ffi'

_M = {}
_M._VERSION = '0.1-alpha'
_M.READ_ONLY = false
_M.WRITE = true

local TXN_INITIAL = 1 -- initial transaction state
local TXN_DONE = 2 -- the transaction has been commited or aborted, and we can dispose the handle
local TXN_RESET = 3 -- the transaction was reset and can be resurected
local TXN_DIRTY = 4 -- the transaction has uncommited changes

local CUR_UNINITIALIZED = 1 -- cursor is uninitialized
local CUR_INITIALIZED = 2 -- cursor is uninitialized
local CUR_SEEKED = 3 -- cursor is seeked to an element from which the iteration starts

-- store structures metadata in a wekreaf table
local _data = setmetatable({},{__mode = 'k'})

local function _error(code)
    local msg = ffi.string(lmdb.mdb_strerror(code))
    return nil, msg, code
end

--
-- MDB_val magic
--
local MDB_val_mt = {
    __tostring = function(self)
        if self.mv_size == 0 then return '' end
        return ffi.string(self.mv_data, self.mv_size)
    end,
    __len = function(self)
        return tonumber(self.mv_size)
    end,
}

local MDB_val_ct = ffi.metatype('MDB_val', MDB_val_mt)
local function MDB_val(val, len)
    if val == nil and len == nil then
        return MDB_val_ct()
    end
    local val_t, buf = type(val), nil

    if 'number' == val_t then
        val = tostring(val)
    end

    if 'string' == val_t or 'number' == val_t then
        local _len = #val
        if len == true then
            buf = ffi.cast('void*',val)
        else
            buf = ffi.new('char[?]',_len)
            ffi.copy(buf, val, _len)
        end
        len = _len
        return MDB_val_ct(len, buf)
    end

    if (len and val_t == 'cdata') then
        return MDB_val_ct(len, ffi.cast('void*',val))
    end

    if val_t == 'cdata' and val.mv_size then
        return val
    end

    error("MDB_val must be initialized either with 'ctype<struct MDB_val>' or 'string'",3)
end

local function MDB_int_val(val)
    local n = ffi.new('int32_t[1]',{ tonumber(val) })
    return MDB_val_ct(4,n)
end


--
-- LMDB environment related functions
--

local env = {}
function env:__index(k)
    return env[k] or (_data[self] and _data[self][k] or nil)
end

function env:__gc()
    lmdb.mdb_env_close(self)
end

function env:__newindex(k,v)
    if not _data[self] then _data[self] = {} end
    _data[self][k] = v
end

function env:info()
    local info = ffi.new 'MDB_envinfo[1]'
    lmdb.mdb_env_info(self, info)
    info = info[0]
    return {
        map_addr = info.me_mapaddr,
        map_size = tonumber(info.me_mapsize),
        last_pgno = tonumber(info.me_last_pgno),
        last_txnid = tonumber(info.me_last_txnid),
        max_readers = tonumber(info.me_maxreaders),
        num_readers = tonumber(info.me_numreaders)
    }
end

function env:stat()
    local stat = ffi.new 'MDB_stat[1]'
    lmdb.mdb_env_stat(self, stat)
    stat = stat[0]
    return {
        psize = tonumber(stat.ms_psize),
        depth = tonumber(stat.ms_depth),
        branch_pages = tonumber(stat.ms_branch_pages),
        leaf_pages = tonumber(stat.ms_leaf_pages),
        overflow_pages = tonumber(stat.ms_overflow_pages),
        entries = tonumber(stat.ms_entries)
    }
end

function env:sync(force)
    local force = force or false
    rc = lmdb.mdb_env_sync(self, force)
    if rc ~= 0 then
        return _error(rc)
    end
    return true
end

function env:reader_check()
    local readers = ffi.new 'int[1]'
    local rc = lmdb.mdb_reader_check(self._handle, readers)
    if rc ~= 0 then
        return _error(rc)
    end
    return readers[0]
end

function env:path()
    local path = ffi.new 'const char*[1]'
    local rc = lmdb.mdb_env_get_path(self, path)
    if rc ~= 0 then
        return _error(rc)
    end
    return ffi.string(path[0])
end

function env:copy(path)
    assert(path, "You must suply a path to the environment")
    local rc = lmdb.mdb_env_copy(self, path)
    if rc ~= 0 then
        return _error(rc)
    end
    return true
end

function env:db_open(name, options, txn)
    local _options = {
        reverse_keys = false,
        integer_keys = false,
        dupsort = false,
        create = true
    }
    -- print(self.db)
    if options then
        _options = _.extend(_options, options)
    end
    options = _options
    local db = nil
    for k,v in pairs(self.dbs) do
        if v.name == name then
            db = v
            break
        end
    end

    if db then
        for k,v in pairs(options) do
            if not db.options or db.options[k] ~= v then
                return nil, "Database was already opened with ".. k .."=" .. tostring(db.options[k]) .. " but '" .. tostring(v) .. " was given", 10000 + 1
            end
        end
        return db[_handle]
    end

    local flags = 0
    if options.reverse_keys then flags = bit.bor(flags, lmdb.MDB_REVERSEKEY) end
    if options.dupsort then
        flags = bit.bor(flags, lmdb.MDB_DUPSORT)
        if options.dupsort == 'integer' then
            flags = bit.bor(flags, lmdb.MDB_INTEGERDUP)
        elseif options.dupsort == 'reverse' then
            flags = bit.bor(flags, lmdb.MDB_REVERSEDUP)
        end
    end
    if options.create then flags = bit.bor(flags, lmdb.MDB_CREATE) end
    if options.integer_keys then flags = bit.bor(flags, lmdb.MDB_INTEGERKEY) end
    local dbi = ffi.new 'MDB_dbi[1]'
    local rc = 0

    if txn then
        rc = lmdb.mdb_dbi_open(txn,name,flags,dbi)
    else
        self:transaction(function(txn)
            rc = lmdb.mdb_dbi_open(txn,name,flags,dbi)
        end, not self.read_only)
    end
    if rc ~= 0 then
        return _error(rc)
    end
    self.dbs[dbi[0]] = { _handle = dbi[0], name = name, options = options }
    return dbi[0]
end

function env:transaction(callback, write, db)
    if write and self.read_only then
        error("Cannot start an write transaction on an read-only opened envrionment")
    end
    local flags = not write and lmdb.MDB_RDONLY or 0
    local txn = ffi.new 'MDB_txn* [1]'
    local rc = lmdb.mdb_txn_begin(self, nil, flags, txn)
    if rc ~= 0 then
        return _error(rc)
    end
    txn = txn[0]
    ffi.gc(txn, txn.__gc)
    txn.read_only = (not write)

    txn.db = db or (self.dbs[1] and self.dbs[1]._handle or nil)

    txn.env = self
    callback(txn)
    if write and not txn.state ~= TXN_DONE then
        local result, msg, rc = txn:commit()
        if not result then return txn, msg, rc end
    end
    if not write and txn.state ~= TXN_DONE then
        txn:reset()
    end
    return true
end


local txn = {}
function txn:__index(k)
    return txn[k] or (_data[self] and _data[self][k] or nil)
end

function txn:__newindex(k,v)
    if not _data[self] then _data[self] = {} end
    _data[self][k] = v
end

function txn:__gc()
    if self.state ~= TXN_DONE then
        self:abort()
    end
end

function txn:commit()
    if self.state == TXN_DONE then
        error("The transaction is finished.", 4)
    end
    local rc = lmdb.mdb_txn_commit(self)
    if rc ~= 0 then
        return _error(rc)
    end
    self.state = TXN_DONE
    return true
end

function txn:reset()
    if not self.read_only then
        error("Cannot reset a write transaction.", 4)
    end

    if self.state == TXN_DONE then
        error("The transaction is finished.", 4)
    end

    lmdb.mdb_txn_reset(self)
    self.state = TXN_RESET
end

function txn:renew()
    if not self.read_only then
        error("Cannot renew a write transaction.", 4)
    end
    if self._aborted then
        error("Cannot renew an aborted transaction.", 4)
    end

    -- local rc = lmdb.mdb_txn_renew(self._handle)
    local rc = lmdb.mdb_txn_renew(self)
    if rc ~= 0 then
        return nil, get_error(rc), rc
    end
    self.state = TXN_INITIAL
    return true
end

function txn:abort()
    if self.state == TXN_DONE then
        return
    end
    -- lmdb.mdb_txn_abort(self._handle)
    lmdb.mdb_txn_abort(self)
    self.state = TXN_DONE
end

function txn:put(key, value, options, db)
    if self.state == TXN_DONE then
        error("The transaction is finished.")
    end
    if self.read_only then
        error("Transaction is read only.")
    end
    local db = db or self.db
    local db_options = self.env.dbs[db].options
    local _options = {
        dupdata = true,
        overwrite = true,
        append = false,
    }
    if options then
        _options = _.extend(_options, options)
    end
    options = _options

    local flags = 0
    if not options.dupdata then flags = bit.bor(flags, lmdb.MDB_NODUPDATA) end
    if not options.overwrite then flags = bit.bor(flags, lmdb.MDB_NOOVERWRITE) end
    if options.append then flags = bit.bor(flags, lmdb.MDB_APPEND) end

    local key = db_options.integer_keys and MDB_int_val(key) or MDB_val(key)
    local value = MDB_val(value)
    local rc = lmdb.mdb_put(self,db,key,value,flags)
    if rc == lmdb.MDB_KEYEXIST then
        return false
    end

    if rc ~= 0 then
        return _error(rc)
    end

    self.state = TXN_DIRTY
    return true
end

function txn:get(key, db)
    if self.state == TXN_DONE or self.state == TXN_RESET then
        error("The transaction is finished.")
    end

    local db = db or self.db
    local db_options = self.env.dbs[db].options

    local key = db_options.integer_keys and MDB_int_val(key) or MDB_val(key)
    local value = MDB_val()

    local rc = lmdb.mdb_get(self, db, key, value)
    if rc == lmdb.MDB_NOTFOUND then return nil end
    if rc ~= 0 then
        return _error(rc)
    end
    return value
end

function txn:del(key, value, db)
    if self.state == TXN_DONE then
        error("The transaction is finished.")
    end
    if self.read_only then
        error("Transaction is read only.")
    end

    local db = db or self.db
    local db_options = _data[db]

    local key = db_options.integer_keys and MDB_int_val(key) or MDB_val(key)
    if value then value = MDB_val(value) end

    local rc = lmdb.mdb_del(self, db, key, value)
    if rc ~= 0 then
        return _error(rc)
    end
    self.state = TXN_DIRTY
    return true
end

function txn:cursor(db)
    local cursor = ffi.new 'MDB_cursor *[1]';
    local db = db or self.db
    local db_options = self.env.dbs[db].options

    local rc = lmdb.mdb_cursor_open(self, db, cursor)
    if rc ~= 0 then
        return _error(rc)
    end
    cursor = cursor[0]
    cursor.state = CUR_UNINITIALIZED
    cursor.db_options = db_options
    return cursor
end

local cursor = {}
function cursor:__index(k)
    return cursor[k] or (_data[self] and _data[self][k] or nil)
end

function cursor:__newindex(k,v)
    if not _data[self] then _data[self] = {} end
    _data[self][k] = v
end


function cursor:iter(options)
    local i = 0
    local _options = {
        reverse = false,
    }
    if options then
        _options = _.extend(_options, options)
    end
    options = _options

    return function()
        local key, value = MDB_val(), MDB_val()

        local op = lmdb.MDB_NEXT
        if options.reverse then
            op = lmdb.MDB_PREV
        end

        if self.state == CUR_UNINITIALIZED then
            self.state = CUR_INITIALIZED
            op = lmdb.MDB_FIRST
            if options.reverse then
                op = lmdb.MDB_LAST
            end
        elseif self.state == CUR_SEEKED then
            op = lmdb.MDB_GET_CURRENT
            self.state = CUR_INITIALIZED
        end

        local rc = lmdb.mdb_cursor_get(self, key, value, op)
        if rc == lmdb.MDB_NOTFOUND then return nil end
        if rc ~= 0 then
            error('cursor error')
        end
        if self.db_options.integer_keys then
            local key = ffi.cast('int32_t *', key.mv_data)
            return tonumber(key[0]), value
        end
        return tostring(key), value
    end
end

function cursor:seek(key, range)
    local key = self.db_options.integer_keys and MDB_int_val(key) or MDB_val(key)
    local value = MDB_val()
    self.state = CUR_UNINITIALIZED
    local op = lmdb.MDB_SET
    if range then
        op = lmdb.MDB_SET_RANGE
    end
    local rc = lmdb.mdb_cursor_get(self, key, nil, op)
    if rc == lmdb.MDB_NOTFOUND then return nil end
    if rc ~= 0 then
        error('cursor error')
    end
    self.state = CUR_SEEKED
    local rc = lmdb.mdb_cursor_get(self, key, value, lmdb.MDB_GET_CURRENT)
    if rc == lmdb.MDB_NOTFOUND then return nil end
    if rc ~= 0 then
        error('cursor error')
    end

    if self.db_options.integer_keys then
        local key = ffi.cast('int32_t *', key.mv_data)
        return tonumber(key[0]), value
    end
    return tostring(key), value
end

--
-- Setup structures metatables
--
ffi.metatype('MDB_env', env)
ffi.metatype('MDB_txn', txn)
ffi.metatype('MDB_cursor', cursor)


--
-- Public Module Interface
--
function _M.environment(path, options)
    assert(path, "You must suply a path to the environment")
    local _options = {
        -- FS options
        mode = 0644,
        size = 10485760,
        -- mdb_env_open flags
        subdir = true,
        read_only = false,
        metasync = true,
        writemap = false,
        map_async = false,
        sync = true,
        lock = true,
        -- runtime setable options
        max_readers = 126,
        max_dbs = 0,
    }
    if options then
        _options = _.extend(_options, options)
    end
    options = _options

    -- Create an MDB_env
    local env, rc = ffi.new 'MDB_env *[1]', nil
    rc = lmdb.mdb_env_create(env)
    if rc ~= 0 then
        return _error(rc)
    end
    env = env[0]
    ffi.gc(env,env.__gc)

    -- Setup maximum nummber of readers
    rc = lmdb.mdb_env_set_maxreaders(env, options.max_readers)
    if rc ~= 0 then
        return _error(rc)
    end

    -- Setup the maxium number of databases
    rc = lmdb.mdb_env_set_maxdbs(env, options.max_dbs)
    if rc ~= 0 then
        return _error(rc)
    end

    -- Setup the database size
    rc = lmdb.mdb_env_set_mapsize(env, options.size)
    if rc ~= 0 then
        return _error(rc)
    end

    -- Setup initial flags
    local flags = lmdb.MDB_NOTLS
    if not options.subdir then flags = bit.bor(flags, lmdb.MDB_NOSUBDIR) end
    if not options.metasync then flags = bit.bor(flags, lmdb.MDB_NOMETASYNC) end
    if options.read_only then flags = bit.bor(flags, lmdb.MDB_RDONLY) end
    if options.writemap then flags = bit.bor(flags, lmdb.MDB_WRITEMAP) end
    if options.map_async then flags = bit.bor(flags, lmdb.MDB_MAPASYNC) end
    if not options.sync then flags = bit.bor(flags, lmdb.MDB_NOSYNC) end
    if not options.lock then flags = bit.bor(flags, lmdb.MDB_NOLOCK) end

    -- Open the environment
    rc = lmdb.mdb_env_open(env, path, flags, tonumber(options['mode'],8))
    if rc ~= 0 then
        return _error(rc)
    end

    env.read_only = options.read_only
    env.dbs = {}
    -- always open and cache the default database
    env:transaction(function(txn)
        db = env:db_open(nil,nil,txn)
    end,_M.READ_ONLY)
    return env
end

function _M.version()
    local major, minor, patch = ffi.new 'int[1]', ffi.new 'int[1]', ffi.new 'int[1]';
    local ver = ffi.string(lmdb.mdb_version(major, minor, patch))
    return ver, major[0], minor[0], patch[0]
end

_M.data = _data
return _M
