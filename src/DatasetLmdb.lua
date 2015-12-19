local pathCache = package.path
package.path = '../third_party/lmdb-lua-ffi/src/?.lua'
local lmdb = require('lmdb')
package.path = pathCache
local Image = require('image')

local DatasetLmdb = torch.class('DatasetLmdb')


function DatasetLmdb:__init(lmdbPath, batchSize, imageType)
    self.batchSize = batchSize or -1
    self.imageType = imageType or 'jpg'
    self:loadDataset(lmdbPath)
end


function DatasetLmdb:loadDataset(lmdbPath)
    self.env = lmdb.environment(lmdbPath, {subdir=false, max_dbs=8, size=1099511627776})
    self.env:transaction(function(txn)
        self.nSamples = tonumber(tostring(txn:get('num-samples')))
    end)
end


function DatasetLmdb:getNumSamples()
    return self.nSamples
end


function DatasetLmdb:getImageGtLexicon(idx, getLexicon)
    getLexicon = getLexicon or false
    local img, label, lexiconList
    self.env:transaction(function(txn)
        local imageKey = string.format('image-%09d', idx)
        local labelKey = string.format('label-%09d', idx)
        local imageBin = tostring(txn:get(imageKey))
        label = tostring(txn:get(labelKey))
        local imageByteLen = string.len(imageBin)
        local imageBytes = torch.ByteTensor(imageByteLen)
        imageBytes:storage():string(imageBin)
        img = Image.decompress(imageBytes, 3, 'byte')
        -- local imgGray = Image.rgb2y(img)
        -- imgGray = Image.scale(imgGray, imgW, imgH)
        -- images[i]:copy(imgGray)
        -- labelList[i] = labelBin
        if getLexicon then
            local lexiconKey = string.format('lexicon-%09d', idx)
            local lexicon = tostring(txn:get(lexiconKey))
            lexiconList = {}
            string.gsub(lexicon, "(%w+)", function (w)
                table.insert(lexiconList, w)
            end)
        end
    end)
    return img, label, lexiconList
end


function DatasetLmdb:allImageLabel(nSampleMax)
    local imgW, imgH = 100, 32
    nSampleMax = nSampleMax or math.huge
    local nSample = math.min(self.nSamples, nSampleMax)
    local images = torch.ByteTensor(nSample, 1, imgH, imgW)
    local labelList = {}
    self.env:transaction(function(txn)
        for i = 1, nSample do
            local imageKey = string.format('image-%09d', i)
            local labelKey = string.format('label-%09d', i)
            local imageBin = tostring(txn:get(imageKey))
            local labelBin = tostring(txn:get(labelKey))
            local imageByteLen = string.len(imageBin)
            local imageBytes = torch.ByteTensor(imageByteLen)
            imageBytes:storage():string(imageBin)
            local img = Image.decompress(imageBytes, 3, 'byte')
            img = Image.rgb2y(img)
            img = Image.scale(img, imgW, imgH)
            images[i]:copy(img)
            labelList[i] = labelBin
        end
    end)
    local labels = str2label(labelList, gConfig.maxT)
    return images, labels
end


function DatasetLmdb:nextBatch()
    local imgW, imgH = 100, 32
    local randomIndex = torch.LongTensor(self.batchSize):random(1, self.nSamples)
    local imageList, labelList = {}, {}

    -- load image binaries and labels
    local success, msg, rc = self.env:transaction(function(txn)
        for i = 1, self.batchSize do
            local idx = randomIndex[i]
            local imageKey = string.format('image-%09d', idx)
            local labelKey = string.format('label-%09d', idx)
            local imageBin = txn:get(imageKey)
            local labelBin = txn:get(labelKey)
            imageList[i] = tostring(imageBin)
            labelList[i] = tostring(labelBin)
        end
    end)

    -- decode images
    local images = torch.ByteTensor(self.batchSize, 1, imgH, imgW)
    for i = 1, self.batchSize do
        local imgBin = imageList[i]
        local imageByteLen = string.len(imgBin)
        local imageBytes = torch.ByteTensor(imageByteLen):fill(0)
        imageBytes:storage():string(imgBin)
        local img = Image.decompress(imageBytes, 3, 'byte')
        img = Image.rgb2y(img)
        img = Image.scale(img, imgW, imgH)
        images[i]:copy(img)
    end
    local labels = str2label(labelList, gConfig.maxT)

    collectgarbage()
    return images, labels
end
