Convolutional Recurrent Neural Network
======================================

This software implements the Convolutional Recurrent Neural Network (CRNN), a combination of CNN, RNN and CTC loss for image-based sequence recognition tasks, such as scene text recognition and OCR. For details, please refer to our paper http://arxiv.org/abs/1507.05717.

**UPDATE Mar 14, 2017** A Docker file has been added to the project. Thanks to [@varun-suresh](https://github.com/varun-suresh).

**UPDATE May 1, 2017** A PyTorch [port](https://github.com/meijieru/crnn.pytorch) has been made by [@meijieru](https://github.com/meijieru).

**UPDATE Jun 19, 2017** For an end-to-end text detector+recognizer, check out the [CTPN+CRNN implementation](https://github.com/AKSHAYUBHAT/DeepVideoAnalytics/tree/master/notebooks/OCR) by [@AKSHAYUBHAT](https://github.com/AKSHAYUBHAT).

Build
-----

The software has only been tested on Ubuntu 14.04 (x64). CUDA-enabled GPUs are required. To build the project, first install the latest versions of [Torch7](http://torch.ch), [fblualib](https://github.com/facebook/fblualib) and LMDB. Please follow their installation instructions respectively. On Ubuntu, lmdb can be installed by ``apt-get install liblmdb-dev``.

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
    
Another example:
![Example Image2](./data/demo2.jpg)

    Recognized text: shakeshack (raw: ss-h-a--k-e-ssh--aa-c--k--)


Use pretrained model
--------------------

The pretrained model can be used for lexicon-free and lexicon-based recognition tasks. Refer to the functions ``recognizeImageLexiconFree`` and ``recognizeImageWithLexicion`` in file ``utilities.lua`` for details.


Train a new model
-----------------

Follow the following steps to train a new model on your own dataset.

  1. Create a new LMDB dataset. A python program is provided in ``tool/create_dataset.py``. Refer to the function ``createDataset`` for details (need to ``pip install lmdb`` first).
  2. Create model directory under ``model/``. For example, ``model/foo_model``. Then create
   configuraton file ``config.lua`` under the model directory. You can copy ``model/crnn_demo/config.lua`` and do modifications.
  3. Go to ``src/`` and execute ``th main_train.lua ../models/foo_model/``. Model snapshots and logging file will be saved into the model directory.


Build using docker
------------------

  1. Install docker. Follow the instructions [here](https://docs.docker.com/engine/installation/)
  2. Install nvidia-docker - Follow the instructions [here](https://github.com/NVIDIA/nvidia-docker)
  3. Clone this repo, from this directory run `docker build -t crnn_docker .`
  4. Once the image is built, the docker can be run using `nvidia-docker run -it crnn_docker`.
  
Citation
--------

Please cite the following paper if you are using the code/model in your research paper.

    @article{ShiBY17,
      author    = {Baoguang Shi and
                   Xiang Bai and
                   Cong Yao},
      title     = {An End-to-End Trainable Neural Network for Image-Based Sequence Recognition
                   and Its Application to Scene Text Recognition},
      journal   = {{IEEE} Trans. Pattern Anal. Mach. Intell.},
      volume    = {39},
      number    = {11},
      pages     = {2298--2304},
      year      = {2017}
    }


Acknowledgements
----------------

The authors would like to thank the developers of Torch7, TH++, [lmdb-lua-ffi](https://github.com/calind/lmdb-lua-ffi) and [char-rnn](https://github.com/karpathy/char-rnn).

Please let me know if you encounter any issues.
