describe("LMDB cursors", function()
    local os = require 'os'
    local lmdb = require 'lmdb'
    local utils = require 'utils'
    local dump = utils.dump
    local testdb = './db/test-10k'
    local env, msg = nil
    local intdb = nil

    setup(function()
        env, msg = lmdb.environment(testdb, {subdir = false, max_dbs=8})
        intdb = env:db_open('int_db', {integer_keys = true})
        env:transaction(function(txn)
            for i=1,100 do
                txn:put(101 - i, 101 - i)
            end
        end, lmdb.WRITE, intdb)
    end)

    teardown(function()
        env = nil
        msg = nil
        collectgarbage()
        os.remove(testdb)
        os.remove(testdb .. '-lock')
    end)

    it("checks cursor simple iteration", function()
        env:transaction(function(txn)
            local i, c = 1, txn:cursor()
            for k,v in c:iter() do
                assert.equals(k, tonumber(tostring(v)))
                assert.equals(k,i)
                i = i + 1
            end
        end, lmdb.READ_ONLY, intdb)
    end)

    it("checks cursor reverse iteration", function()
        env:transaction(function(txn)
            local i, c = 100, txn:cursor()
            for k,v in c:iter({reverse = true}) do
                assert.equals(k, tonumber(tostring(v)))
                assert.equals(k,i)
                i = i - 1
            end
        end, lmdb.READ_ONLY, intdb)
    end)

    it("checks cursor seek", function()
        env:transaction(function(txn)
            local i, c =  50, txn:cursor()
            assert.equals(50, tonumber(tostring(c:seek(50))))
            i = 50
            for k,v in c:iter() do
                assert.equals(k, tonumber(tostring(v)))
                assert.equals(k,i)
                i = i + 1
            end
        end, lmdb.READ_ONLY, intdb)
    end)

    it("checks cursor seek not found", function()
        env:transaction(function(txn)
            local c = txn:cursor()
            assert.is_nil(c:seek(101))
        end, lmdb.READ_ONLY, intdb)
    end)

    it("checks cursor iteration after seek not found", function()
        env:transaction(function(txn)
            local i, c =  1, txn:cursor()
            assert.is_nil(c:seek(0))
            for k,v in c:iter() do
                assert.equals(k, tonumber(tostring(v)))
                assert.equals(k,i)
                i = i + 1
            end
        end, lmdb.READ_ONLY, intdb)
    end)

    it("checks cursor seek first found", function()
        env:transaction(function(txn)
            local c = txn:cursor()
            local k,v = c:seek(0, true)
            assert.equals(1, k)
        end, lmdb.READ_ONLY, intdb)
    end)
end)
