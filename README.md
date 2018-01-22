# lib-ml-databox [![docs](https://img.shields.io/badge/doc-online-blue.svg)](https://seveneng.github.io/lib-ml-databox/)
A OCaml/Reason library for interfacing with Databox APIs

### Usage

#### Develop natively
Install this library through opam:
```
git clone https://github.com/sevenEng/lib-ml-databox.git
cd lib-ml-databox
opam pin add lib-databox .
```

#### Containerize your application
Use the `Dockerfile`
under the root directory to builds a docker image with this library embedded.

### Documentation
#### APIs
Please refer to [the Github Pages of this repository](https://seveneng.github.io/lib-ml-databox/),
where a web version of the documentation could be queried.
Meanwhile there are other implementations that could be used to do cross-reference:
+ [lib-node-databox](https://github.com/me-box/lib-node-databox),
+ [lib-go-databox](https://github.com/me-box/lib-go-databox),
+ [lib-python-databox](https://github.com/me-box/lib-python-databox).

#### Samples
There are simple driver and app samples in the directory `samples/`, which basically shows how to use this library.

#### Others
If you're wondering about the whole databox systems, and how drivers, apps, stores are interacting with each other,
with different system components, some useful documentations are gathered [here](https://github.com/me-box/documents).
