VV Framework
============

This repository is a microservices framework where you can group multiple services under a chosen category, In which you can also run multiple different categories.
It is designed to consist of multiple containers each responsible for a single entity, where it has it's own Postgresql Database attached to it.
However all communication between services is using the dynamic underlying transport layer which is now set to be Redis. In fact not only communication is over Redis, but services will maintain a copy of the entity data they are responsible for in Redis too. In this way the framework will be more robust since everything will be available on Redis and it there will be very rare queries on Postgresql, only if data does not exist because maybe it was too old, making Postgres acting like a cold storage.

The framework is designed to make it easy for new components to be added. As all what you need is to write one Class within the directory of its category, and then run `bin/docker-compose-services.pl` and it will (re)generate `docker-compose.yml` file that will have updated/added the  definition of all needed services along with the supporting infrastructure needed, like Redis Cluster, Postgresql database for every service, a registry container for images.

Giving the purpose of this Framework, It was mainly build with these packages:
- Future
- IO::Async::Loop
- IO::Async::Notifier
- Object::Pad

## Extra

This framework also implements its own IO::Loop utilizing none blocking `epoll` calls for asynchronous performance.
- Main VLoop class: `VV::Framework::Loop::VLoop`
- Epoll Socket: `VV::Framework::Loop::Socket`
- Example async http request that adds number to array while making request. `bin/vloop-example.pl`

### Structure

For better understanding let me walk you through directory structure:

- bin/
  - `docker-compose-services.pl` this is used to (re)generate docker-compose file by traversing through directories and classes adding a new docker service definition for each one found.
  - `vv-start.pl` bootstrapping script that will run everything. It is set to be the Entrypoint of services containers.
- lib/VV
  - this is where `VV::Framework` packages, and it will be installed in containers running services.
- services/
  - this is where our services packages will be.
  - structured this way `/service/<app>/<component>`
  - and then `/service/<app>/<component>/lib` for service packages, this `lib` path will be added in the service dedicated container.
  - `/service/<app>/<component>/aptfile` and `/service/<app>/<component>/cpanfile` for any specific extra dependencies to be installed in container for this service.
- redis-cluster-proxy/
  - Redis cluster proxy, forked and modified repository in order to run Redis Cluster properly.
- docker-compose.yml.tt2
  - this file is used as the base template to generate docker-compose.yml
- Dockerfile
  - have the base image for VV::Framework
- Bunch of other files for `dzil` and Redis configuration file, along with .pg_service.conf

### Caffeine-Manager (app)

- `services/caffeine-manager`
  - api
  - user
  - machine
  - coffee
  - stats
- with each having `lib/Service/<name>.pm`, `Dockerfile`, `cpanfile` and `aptfile`

## Usage

### Build

To have it up and running, all what you need to do is:

```
git clone --recursive git@github.com:vnealv/perl-VV-Framework.git
cd perl-VV-Framework .

docker build -t perl-vv-framework .
docker-compose up .-d
```

if you want to add/remove services. Just add the service package file.
- Just add your service in `services` directory
- run `perl bin/docker-compose-services.pl` in order to update `docker-compose.yml` file to reflect your changes.
- then `docker-compose up -d` to apply it.

