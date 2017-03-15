# Start with a base docker image that contains torch and cutorch.
FROM kaixhin/cuda-torch

# Install fblualib and its dependencies :
ADD install_all.sh /root/install_all.sh
ADD thpp_build.sh /root/thpp_build.sh

WORKDIR /root
RUN chmod +x ./install_all.sh
RUN ./install_all.sh

# Clone the crnn repo :
RUN git clone https://github.com/bgshih/crnn.git
RUN apt-get update && apt-get install -y \
		liblmdb-dev

WORKDIR /root/crnn/src
RUN chmod +x build_cpp.sh
RUN ./build_cpp.sh
