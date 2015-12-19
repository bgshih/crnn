describe("LMDB revese keys", function()
    local os = require 'os'
    local lmdb = require 'lmdb'
    local utils = require 'utils'
    local dump = utils.dump
    local testdb = './db/test-rev'
    local env, msg = nil
    local revdb = nil
    local data = {19,28,37,46,55,64,73,82,91}

    setup(function()
        os.remove(testdb)
        os.remove(testdb .. '-lock')
        env, msg = lmdb.environment(testdb, {subdir = false, max_dbs=8})
        revdb = env:db_open('rev_db', { reverse_keys = true })
        env:transaction(function(txn)
            for i=1,9 do
                txn:put(data[i],10 - i)
            end
        end, lmdb.WRITE, revdb)
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
            local i, c = 9, txn:cursor()
            for k,v in c:iter() do
                assert.equals(k, tostring(i * 10 + 10 - i))
                i = i - 1
            end
        end, lmdb.READ_ONLY, revdb)
    end)

    it("checks cursor reverse iteration", function()
        env:transaction(function(txn)
            local i, c = 1, txn:cursor()
            for k,v in c:iter({reverse = true}) do
                assert.equals(k, tostring(i * 10 + 10 - i))
                i = i + 1
            end
        end, lmdb.READ_ONLY, revdb)
    end)
end)
