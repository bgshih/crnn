local _ = require 'underscore'
local bit = require 'bit'
local ffi = require "ffi"
local lmdb = require "lmdb_ffi"
local utils = require 'utils'

_M = {}
_M._VERSION = "0.1-alpha"
_M.READ_ONLY = false
_M.WRITE = true

local _envs = setmetatable({},{__mode = 'v'})

local TXN_INITIAL = 1 -- initial transaction state
local TXN_DONE = 2 -- the transaction has been commited or aborted, and we can dispose the handle
local TXN_RESET = 3 -- the transaction was reset and can be resurected
local TXN_DIRTY = 4 -- the transaction has uncommited changes

local CUR_INITAL = 1 -- the cursor is in an unpositioned, initial state
local CUR_POSITIONED = 2 -- the cursor was seeked at least once
local CUR_RESET = 3 -- the cursor can be renewed with cur:renew()
local CUR_CLOSED = 4 -- the cursor is colsed

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

local env = {}
local env_mt = {
    __index = env,
}

local txn = {}
local txn_mt = {
    __index = txn,
}

local db = {}
local db_mt = {
    __index = db
}

local cur = {}
local cur_mt = {
    __index = cur
}


local function cursor_close(cursor)
    print('Closing cursor ' .. tostring(cursor))
    lmdb.mdb_cursor_close(cursor)
end

local function _close_bound_cursors(txn)
    for i, cursor in pairs(txn.cursors) do
        cursor_close(cursor._handle)
        cursor._handle = nil
        txn.cursors[i] = nil
    end
end

local function env_close(env)
    local env_key = tostring(env)
    local env = _envs[env_key]
    if env then
        for _,txn in pairs(env['txns']) do
            if txn.state ~= TXN_DONE then
                txn:abort()
            end
        end
        _envs[env_key] = nil
        lmdb.mdb_env_close(env._handle)
    end
end

local function get_error(code)
    return ffi.string(lmdb.mdb_strerror(code))
end

function env.open(self, path, options)
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
        return nil, 'Error creating environment: ' .. get_error(rc), rc
    end
    env = ffi.gc(env[0], env_close)

    -- Setup maximum nummber of readers
    rc = lmdb.mdb_env_set_maxreaders(env, options.max_readers)
    if rc ~= 0 then
        return nil, "Error while setting the maxium number of readers: " .. get_error(rc), rc
    end

    -- Setup the maxium number of databases
    rc = lmdb.mdb_env_set_maxdbs(env, options.max_dbs)
    if rc ~= 0 then
        return nil, "Error while setting the number of databases: " .. get_error(rc), rc
    end

    -- Setup the database size
    rc = lmdb.mdb_env_set_mapsize(env, options.size)
    if rc ~= 0 then
        return nil, "Error while setting database size: " .. get_error(rc), rc
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
        return nil, 'Error opening environment' .. get_error(rc), rc
    end
    local db = nil
    self = setmetatable({_handle = env,
                         read_only = options.read_only,
                         dbs = {},
                         txns = setmetatable({},{__mode = 'v'})
                        }, env_mt)
    local txn, msg, rc = self:transaction(function(txn)
        db = self:db_open(nil,nil,txn)
    end,_M.READ_ONLY)
    _envs[tostring(env)] = self
    return self
end

function env.info(self)
    local info = ffi.new 'MDB_envinfo[1]'
    lmdb.mdb_env_info(self._handle, info)
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

function env.stat(self)
    local stat = ffi.new 'MDB_stat[1]'
    lmdb.mdb_env_stat(self._handle, stat)
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

function env.close(self)
    env_close(self._handle)
end

function env.sync(self, force)
    local force = force or false
    rc = lmdb.mdb_env_sync(self._handle, force)
    if rc ~= 0 then
        return nil, "Error while setting database size: " .. get_error(rc), rc
    end
    return true
end

function env.reader_check(self)
    local readers = ffi.new 'int[1]'
    local rc = lmdb.mdb_reader_check(self._handle, readers)
    if rc ~= 0 then
        return nil, get_error(rc), rc
    end
    return readers[0]
end

function env.max_readers(self)
    local readers = ffi.new 'int[1]'
    local rc = lmdb.mdb_env_get_maxreaders(self._handle, readers)
    if rc ~= 0 then
        return nil, get_error(rc), rc
    end
    return readers[0]
end

function env.path(self)
    local path = ffi.new 'const char*[1]'
    local rc = lmdb.mdb_env_get_path(self._handle, path)
    if rc ~= 0 then
        return nil, get_error(rc), rc
    end
    return ffi.string(path[0])
end

function env.copy(self, path)
    local rc = lmdb.mdb_env_copy(self._handle, path)
    if rc ~= 0 then
        return nil, get_error(rc), rc
    end
    return true
end

function env.db_open(self, name, options, txn)
    local _options = {
        reverse_keys = false,
        dupsort = false,
        create = true,
        integer_keys = false
    }
    if options then
        _options = _.extend(_options, options)
    end
    options = _options

    if self.dbs[name or 0] then
        local dbs = self.dbs
        for k,v in pairs(options) do
            print(k,v)
            if dbs[name].options[k] ~= v then
                return nil, "Database was already opened with ".. k .."=" .. tostring(dbs[name].options[k]) .. " but '" .. tostring(v) .. " was given", 10000 + 1
            end
        end
        return dbs[name]
    end

    local flags = 0
    if options.reverse_keys then flags = bit.bor(flags, lmdb.MDB_REVERSEKEY) end
    if options.dupsort then flags = bit.bor(flags, lmdb.MDB_DUPSORT) end
    if options.create then flags = bit.bor(flags, lmdb.MDB_CREATE) end
    if options.integer_keys then flags = bit.bor(flags, lmdb.MDB_INTEGERKEY) end
    local dbi = ffi.new 'MDB_dbi[1]'
    local rc = 0

    if txn then
        rc = lmdb.mdb_dbi_open(txn._handle,name,flags,dbi)
    else
        self:transaction(function(txn)
            rc = lmdb.mdb_dbi_open(txn._handle,name,flags,dbi)
        end, not self.read_only)
    end

    if rc ~= 0 then
        return nil, get_error(rc), rc
    end
    local db = setmetatable({ _handle = dbi[0], options = options }, db_mt)
    self.dbs[name or 0] = db
    return db
end

function env.transaction(self, callback, write, db)
    local txn, msg, rc = txn:begin(self, write, db)
    if not txn then return nil, msg, rc end
    callback(txn)
    if write and not txn.state ~= TXN_DONE then
        local result, msg, rc = txn:commit()
        if not result then return txn, msg, rc end
    end
    if not write and txn.state ~= TXN_DONE then
        txn:reset()
    end
    return txn
end

function txn.begin(self, env, write, db)
    if write and env.read_only then
        error("Cannot start an write transaction on an read-only opened envrionment")
    end
    local flags = not write and lmdb.MDB_RDONLY or 0
    local txn = ffi.new 'MDB_txn* [1]'
    local rc = lmdb.mdb_txn_begin(env._handle, nil, flags, txn)
    if rc ~= 0 then
        return nil, get_error(rc), rc
    end
    txn = txn[0]
    txn = setmetatable({ _handle = txn,
                         read_only = (not write),
                         env = env,
                         db = db or env.dbs[0],
                         cursors = setmetatable({},{__mode = 'v'}),
                         state=TXN_INITIAL }, txn_mt)
    table.insert(env['txns'], txn)
    return txn
end

function txn.commit(self)
    if self.state == TXN_DONE then
        error("The transaction is finished.", 4)
    end
    _close_bound_cursors(self)
    local rc = lmdb.mdb_txn_commit(self._handle)
    if rc ~= 0 then
        return nil, get_error(rc), rc
    end
    self.state = TXN_DONE
    return true
end

function txn.reset(self)
    if not self.read_only then
        error("Cannot reset a write transaction.", 4)
    end

    if self.finished and not self.reset then
        error("The transaction is finished.", 4)
    end

    _close_bound_cursors(self)
    lmdb.mdb_txn_reset(self._handle)
    self.state = TXN_RESET
end

function txn.renew(self)
    if not self.read_only then
        error("Cannot renew a write transaction.", 4)
    end
    if self._aborted then
        error("Cannot renew an aborted transaction.", 4)
    end

    local rc = lmdb.mdb_txn_renew(self._handle)
    if rc ~= 0 then
        return nil, get_error(rc), rc
    end
    self.state = TXN_INITIAL
    return true
end

function txn.abort(self)
    if self.finished and not self._reset then
        return
    end
    _close_bound_cursors(self)
    lmdb.mdb_txn_abort(self._handle)
    self.state = TXN_DONE
end

function txn.put(self, key, value, options, db)
    if self.finished then
        error("The transaction is finished.")
    end
    if self.read_only then
        error("Transaction is read only.")
    end

    local db = db or self.env.dbs[0]

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

    local rc = lmdb.mdb_put(self._handle,db._handle,MDB_val(key,true),MDB_val(value,true), flags)
    if rc == lmdb.MDB_KEYEXIST then
        return nil
    end

    if rc ~= 0 then
        return nil, get_error(rc), rc
    end
    self.state = TXN_DIRTY
    return true
end

function txn.get(self, key, db)
    if self.finished then
        error("The transaction is finished.")
    end

    local db = db or self.env.dbs[0]

    local value = MDB_val()
    local rc = lmdb.mdb_get(self._handle, db._handle, MDB_val(key,true), value)
    if rc == lmdb.MDB_NOTFOUND then return nil end
    if rc ~= 0 then
        return nil, get_error(rc), rc
    end
    return value
end

function txn.del(self, key, value, db)
    if self.finished then
        error("The transaction is finished.")
    end
    if self.read_only then
        error("Transaction is read only.")
    end

    local db = db or self.env.dbs[0]

    if value then value = MDB_val(value) end

    local rc = lmdb.mdb_del(self._handle, db._handle, MDB_val(key), value)
    if rc ~= 0 then
        return nil, get_error(rc), rc
    end
    self.state = TXN_DIRTY
    return true
end

function txn.stat(self, db)
    local db = db or self.env.dbs[0]

    local stat = ffi.new 'MDB_stat[1]'
    local rc = lmdb.mdb_stat(self._handle, db._handle, stat)
    if rc ~= 0 then
        return nil, get_error(rc), rc
    end
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

function txn.cursor(self, db)
    local db = db or self.env.dbs[0]
    return cur:open(db, self)
end

function cur.open(self, db, txn)
    local cursor = ffi.new 'MDB_cursor *[1]'
    rc = lmdb.mdb_cursor_open(txn._handle, db._handle, cursor)
    if rc ~= 0 then
        return nil, get_error(rc), rc
    end
    -- ffi.gc(cursor[0], cursor_close)
    cur = setmetatable({ _handle = cursor[0],
                          state = CUR_INITAL,
                          read_only = txn.read_only,
                        }, cur_mt)
    table.insert(txn.cursors, cur)
    return cur
end

function _M.version()
    local major, minor, patch = ffi.new 'int[1]', ffi.new 'int[1]', ffi.new 'int[1]';
    local ver = ffi.string(lmdb.mdb_version(major, minor, patch))
    return ver, major[0], minor[0], patch[0]
end

function _M.get_error(code)
    return code, get_error(code)
end

_M.cur = cur
_M.env = env
_M.txn = txn
_M.db = db
_M.MDB_val = MDB_val
return _M
