describe("LMDB integer keys", function()
    local os = require 'os'
    local lmdb = require 'lmdb'
    local utils = require 'utils'
    local dump = utils.dump
    local testdb = './db/test-10k'
    local env, msg = nil
    local int_db = nil

    setup(function()
        env, msg = lmdb.environment(testdb, {subdir = false, max_dbs=8})
        int_db = env:db_open( 'int_keys', {integer_keys = true})
        env:transaction(function(txn)
            for i=1,10000 do
                txn:put(i,i)
            end
        end, lmdb.WRITE, int_db)
    end)

    teardown(function()
        env = nil
        msg = nil
        collectgarbage()
        os.remove(testdb)
        os.remove(testdb .. '-lock')
    end)

    it("checks get on test database", function()
        assert.is_nil(msg)
        env:transaction(function(txn)
            for i=1,10000 do
                local got_value = tonumber(tostring(txn:get(i)))
                assert.equals(i, got_value)
            end
        end, lmdb.READ_ONLY, int_db)
    end)
end)
