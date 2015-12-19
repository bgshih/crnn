Convolutional Recurrent Neural Network
======================================

This software implements the Convolutional Recurrent Neural Network (CRNN), a combination of CNN, RNN and CTC loss for image-based sequence recognition tasks, such as scene text recognition and OCR. For details, please refer to our paper http://arxiv.org/abs/1507.05717.


Build
-----

The software has only been tested on Ubuntu 14.04 (x64). CUDA-enabled GPUs are required. To build the project, first install [Torch7](http://torch.ch), [TH++](https://github.com/facebook/thpp) and LMDB. Please follow their installation instructions. On Ubuntu, lmdb can be installed by ``apt-get install liblmdb-dev``.

To build the project, go to ``src/`` and execute ``sh build_cpp.sh`` to build the C++ code. If successful, a file named ``libcrnn.so`` should be produced in the ``src/`` directory.


Run demo
--------

A demo program can be found in ``src/demo.lua``. Before running the demo, download a pretrained model from [here](https://www.dropbox.com/s/tx6cnzkpg99iryi/crnn_demo_model.t7?dl=0). Put the downloaded model file ``crnn_demo_model.t7`` into directory ``model/crnn_demo/``. Then launch the demo by:

    th demo.lua

The demo reads an example image and recognizes its text content.

Example image:
![Example Image](./data/demo.png)

Expected output:

    Loading model...
    Model loaded from ../model/crnn_demo/model.t7
    Recognized text: available (raw: a-----v--a-i-l-a-bb-l-e---)


Use pretrained model
--------------------

The pretrained model can be used for lexicon-free and lexicon-based recognition tasks. Refer to the functions ``recognizeImageLexiconFree`` and ``recognizeImageWithLexicion`` in file ``utilities.lua`` for details.


Train a new model
-----------------

Follow the following steps to train a new model on your own dataset.

  1. Create a new LMDB dataset. A python program is provided in ``tool/create_dataset.py``. Refer to the function ``createDataset`` for details.
  2. Create model directory under ``model/``. For example, ``model/foo_model``. Then create 
   configuraton file ``config.lua`` under the model directory. You can copy ``model/crnn_demo/config.lua`` and do modifications.
  3. Go to ``src/`` and execute ``th main_train.lua ../models/foo_model/``. Model snapshots and logging file will be saved into the model directory.


Citation
--------

Please cite the following paper if you are using the code/model in your research paper.

    @article{ShiBY15,
      author    = {Baoguang Shi and
                   Xiang Bai and
                   Cong Yao},
      title     = {An End-to-End Trainable Neural Network for Image-based Sequence Recognition
                   and Its Application to Scene Text Recognition},
      journal   = {CoRR},
      volume    = {abs/1507.05717},
      year      = {2015}
    }


Acknowledgements
----------------

The authors would like to thank the developers of Torch7, TH++, [lmdb-lua-ffi](https://github.com/calind/lmdb-lua-ffi) and [char-rnn](https://github.com/karpathy/char-rnn).

Please let me know if you encounter any issues.
