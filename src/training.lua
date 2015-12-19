function trainModel(model, criterion, trainSet, testSet)
    -- get model parameters
    local params, gradParams = model:getParameters()
    local optimMethod = gConfig.optimMethod
    local optimState = gConfig.optimConfig

    function trainBatch(inputBatch, targetBatch)
        --[[ One step of SGD training
        ARGS:
          - `inputBatch`  : batch of inputs (images)
          - `targetBatch` : batch of targets (groundtruth labels)
        ]]
        model:training()
        local nFrame = inputBatch:size(1)
        local feval = function(p)
            if p ~= params then
                params:copy(x)
            end
            gradParams:zero()
            local outputBatch = model:forward(inputBatch)
            local f = criterion:forward(outputBatch, targetBatch)
            model:backward(inputBatch, criterion:backward(outputBatch, targetBatch))
            gradParams:div(nFrame)
            f = f / nFrame
            return f, gradParams
        end
        local _, loss = optimMethod(feval, params, optimState); loss = loss[1]
        return loss
    end

    function validation(input, target)
        --[[ Do validation
        ARGS:
          - `input`  : validation inputs
          - `target` : validation targets
        ]]
        logging('Validating...')
        model:evaluate()

        -- batch feed forward
        local batchSize = gConfig.valBatchSize
        local nFrame = input:size(1)
        local output = torch.Tensor(nFrame, gConfig.maxT, gConfig.nClasses+1)
        for i = 1, nFrame, batchSize do
            local actualBatchSize = math.min(batchSize, nFrame-i+1)
            local inputBatch = input:narrow(1,i,actualBatchSize)
            local outputBatch = model:forward(inputBatch)
            output:narrow(1,i,actualBatchSize):copy(outputBatch)
        end

        -- compute loss
        local loss = criterion:forward(output, target, true) / nFrame

        -- decoding
        local pred, rawPred = naiveDecoding(output)
        local predStr = label2str(pred)

        -- compute recognition metrics
        local gtStr = label2str(target)
        local nCorrect = 0
        for i = 1, nFrame do
            if predStr[i] == string.lower(gtStr[i]) then
                nCorrect = nCorrect + 1
            end
        end
        local accuracy = nCorrect / nFrame
        logging(string.format('Test loss = %f, accuracy = %f', loss, accuracy))

        -- show prediction examples
        local rawPredStr = label2str(rawPred, true)
        for i = 1, math.min(nFrame, gConfig.nTestDisplay) do
            local idx = math.floor(math.random(1, nFrame))
            logging(string.format('%25s  =>  %-25s  (GT:%-20s)',
                rawPredStr[idx], predStr[idx], gtStr[idx]))
        end
    end

    -- train loop
    local iterations = 0
    local loss = 0
    while true do
        -- validation
        if iterations == 0 or iterations % gConfig.testInterval == 0 then
            local valInput, valTarget = testSet:allImageLabel(5000)
            validation(valInput, valTarget)
            collectgarbage()
        end

        -- train batch
        local input, target = trainSet:nextBatch()
        assert(input:nDimension() == 4)
        loss = loss + trainBatch(input, target)
        iterations = iterations + 1

        -- display
        if iterations % gConfig.displayInterval == 0 then
            loss = loss / gConfig.displayInterval
            logging(string.format('Iteration %d - train loss = %f', iterations, loss))
            diagnoseGradients(model:parameters())
            loss = 0
            collectgarbage()
        end

        -- save snapshot
        if iterations > 0 and iterations % gConfig.snapshotInterval == 0 then
            local savePath = paths.concat(gConfig.modelDir, string.format('snapshot_%d.t7', iterations))
            torch.save(savePath, modelState(model))
            logging(string.format('Snapshot saved to %s', savePath))
            collectgarbage()
        end

        -- terminate
        if iterations > gConfig.maxIterations then
            logging('Maximum iterations reached, terminating ...')
            break
        end
    end
end
