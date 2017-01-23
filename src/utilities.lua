local Image = require('image')


function str2label(strs, maxLength)
    --[[ Convert a list of strings to integer label tensor (zero-padded).

    ARGS:
      - `strs`     : table, list of strings
      - `maxLength`: int, the second dimension of output label tensor

    RETURN:
      - `labels`   : tensor of shape [#(strs) x maxLength]
    ]]
    assert(type(strs) == 'table')

    function ascii2label(ascii)
        local label
        if ascii >= 48 and ascii <= 57 then -- '0'-'9' are mapped to 1-10
            label = ascii - 47
        elseif ascii >= 65 and ascii <= 90 then -- 'A'-'Z' are mapped to 11-36
            label = ascii - 64 + 10
        elseif ascii >= 97 and ascii <= 122 then -- 'a'-'z' are mapped to 11-36
            label = ascii - 96 + 10
        end
        return label
    end

    local nStrings = #strs
    local labels = torch.IntTensor(nStrings, maxLength):fill(0)
    for i, str in ipairs(strs) do
        for j = 1, string.len(str) do
            local ascii = string.byte(str, j)
            labels[i][j] = ascii2label(ascii)
        end
    end
    return labels
end


function label2str(labels, raw)
    --[[ Convert a label tensor to a list of strings.

    ARGS:
      - `labels`: int tensor, labels
      - `raw`   : boolean, if true, convert zeros to '-'

    RETURN:
      - `strs`  : table, list of strings
    ]]
    assert(labels:dim() == 2)
    raw = raw or false

    function label2ascii(label)
        local ascii
        if label >= 1 and label <= 10 then
            ascii = label - 1 + 48
        elseif label >= 11 and label <= 36 then
            ascii = label - 11 + 97
        elseif label == 0 then -- used when displaying raw predictions
            ascii = string.byte('-')
        end
        return ascii
    end

    local strs = {}
    local nStrings, maxLength = labels:size(1), labels:size(2)
    for i = 1, nStrings do
        local str = {}
        local labels_i = labels[i]
        for j = 1, maxLength do
            if raw then
                str[j] = label2ascii(labels_i[j])
            else
                if labels_i[j] == 0 then
                    break
                else
                    str[j] = label2ascii(labels_i[j])
                end
            end
        end
        str = string.char(unpack(str))
        strs[i] = str
    end
    return strs
end


function setupLogger(fpath)
    local fileMode = 'w'
    if paths.filep(fpath) then
        local input = nil
        while not input do
            print('Logging file exits, overwrite(o)? append(a)? abort(q)?')
            -- input = io.read()
            input = 'o'
            if input == 'o' then
                fileMode = 'w'
            elseif input == 'a' then
                fileMode = 'a'
            elseif input == 'q' then
                os.exit()
            else
                fileMode = nil
            end
        end
    end
    gLoggerFile = io.open(fpath, fileMode)
end


function tensorInfo(x, name)
    local name = name or ''
    local sizeStr = ''
    for i = 1, #x:size() do
        sizeStr = sizeStr .. string.format('%d', x:size(i))
        if i < #x:size() then
            sizeStr = sizeStr .. 'x'
        end
    end
    infoStr = string.format('[%15s] size: %12s, min: %+.2e, max: %+.2e', name, sizeStr, x:min(), x:max())
    return infoStr
end


function shutdownLogger()
    if gLoggerFile then
        gLoggerFile:close()
    end
end


function logging(message, mute)
    mute = mute or false
    local timeStamp = os.date('%x %X')
    local msgFormatted = string.format('[%s]  %s', timeStamp, message)
    if not mute then
        print(msgFormatted)
    end
    if gLoggerFile then
        gLoggerFile:write(msgFormatted .. '\n')
        gLoggerFile:flush()
    end
end


function modelSize(model)
    local params = model:parameters()
    local count = 0
    local countForEach = {}
    for i = 1, #params do
        local nParam = params[i]:numel()
        count = count + nParam
        countForEach[i] = nParam
    end
    return count, torch.LongTensor(countForEach)
end


function cloneList(tensors, fillZero)
    --[[ Clone a list of tensors, adapted from https://github.com/karpathy/char-rnn
    ARGS:
      - `tensors`  : table, list of tensors
      - `fillZero` : boolean, if true tensors are filled with zeros
    RETURNS:
      - `output`   : table, cloned list of tensors
    ]]
    local output = {}
    for k, v in pairs(tensors) do
        output[k] = v:clone()
        if fillZero then output[k]:zero() end
    end
    return output
end


function cloneManyTimes(net, T)
    --[[ Clone a network module T times, adapted from https://github.com/karpathy/char-rnn
    ARGS:
      - `net`    : network module to be cloned
      - `T`      : integer, number of clones
    RETURNS:
      - `clones` : table, list of clones
    ]]
    local clones = {}
    local params, gradParams = net:parameters()
    local mem = torch.MemoryFile("w"):binary()
    mem:writeObject(net)
    for t = 1, T do
        local reader = torch.MemoryFile(mem:storage(), "r"):binary()
        local clone = reader:readObject()
        reader:close()
        local cloneParams, cloneGradParams = clone:parameters()
        if params then
            for i = 1, #params do
                cloneParams[i]:set(params[i])
                cloneGradParams[i]:set(gradParams[i])
            end
        end
        clones[t] = clone
        collectgarbage()
    end
    mem:close()
    return clones
end


function diagnoseGradients(params, gradParams)
    --[[ Diagnose gradients by checking the value range and the ratio of the norms
    ARGS:
      - `params`     : first arg returned by net:parameters()
      - `gradParams` : second arg returned by net:parameters()
    ]]
    for i = 1, #params do
        local pMin = params[i]:min()
        local pMax = params[i]:max()
        local gpMin = gradParams[i]:min()
        local gpMax = gradParams[i]:max()
        local normRatio = gradParams[i]:norm() / params[i]:norm()
        logging(string.format('%02d - params [%+.2e, %+.2e] gradParams [%+.2e, %+.2e], norm gp/p %+.2e',
            i, pMin, pMax, gpMin, gpMax, normRatio), true)
    end
end


function modelState(model)
    --[[ Get model state, including model parameters (weights and biases) and
         running mean/var in batch normalization layers
    ARGS:
      - `model` : network model
    RETURN:
      - `state` : table, model states
    ]]
    local parameters = model:parameters()
    local bnVars = {}
    local bnLayers = model:findModules('nn.BatchNormalization')
    for i = 1, #bnLayers do
        bnVars[#bnVars+1] = bnLayers[i].running_mean
        bnVars[#bnVars+1] = bnLayers[i].running_var
    end
    local bnLayers = model:findModules('nn.SpatialBatchNormalization')
    for i = 1, #bnLayers do
        bnVars[#bnVars+1] = bnLayers[i].running_mean
        bnVars[#bnVars+1] = bnLayers[i].running_var
    end
    local state = {parameters = parameters, bnVars = bnVars}
    return state
end


function loadModelState(model, stateToLoad)
    local state = modelState(model)
    assert(#state.parameters == #stateToLoad.parameters)
    assert(#state.bnVars == #stateToLoad.bnVars)
    for i = 1, #state.parameters do
        state.parameters[i]:copy(stateToLoad.parameters[i])
    end
    for i = 1, #state.bnVars do
        state.bnVars[i]:copy(stateToLoad.bnVars[i])
    end
end


function loadAndResizeImage(imagePath)
    local img = Image.load(imagePath, 3, 'byte')
    img = Image.rgb2y(img)
    img = Image.scale(img, 100, 32)[1]
    return img
end


function recognizeImageLexiconFree(model, image)
    --[[ Lexicon-free text recognition.
    ARGS:
      - `model`   : CRNN model
      - `image`   : single-channel image, byte tensor
    RETURN:
      - `str`     : recognized string
      - `rawStr`  : raw recognized string
    ]]
    assert(image:dim() == 2 and image:type() == 'torch.ByteTensor',
        'Input image should be single-channel byte tensor')
    image = image:view(1, 1, image:size(1), image:size(2))
    local output = model:forward(image)
    local pred, predRaw = naiveDecoding(output)
    local str = label2str(pred)[1]
    local rawStr = label2str(predRaw, true)[1]
    return str, rawStr
end


function recognizeImageWithLexicion(model, image, lexicon)
    --[[ Text recognition with a lexicon.
    ARGS:
      - `model`: CRNN model
      - `image` : single-channel image, byte tensor
      - `lexicon`   : list of string, lexicon words
    RETURN:
      - `str`       : recognized string
    ]]
    assert(image:dim() == 2 and image:type() == 'torch.ByteTensor',
        'Input image should be single-channel byte tensor')
    image = image:view(1, 1, image:size(1), image:size(2))
    local output = model:forward(image)
    local str = decodingWithLexicon(output, lexicon)
    return str
end
