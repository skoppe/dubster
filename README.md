# Dubster

Runs unittests for each dub packages against latest dmd compiler.

## How does it work?

There are two components, a server and at least one worker. The server checks github and code.dlang.org for releases and new packages. Based on that it creates jobs.

Each worker polls the server for a job. Once a job is returned it starts a docker `skoppe/dubster-digger` container to build DMD (if not already cached). It then uses the fresh dmd and starts a docker `skoppe/dubster-dub` container and starts building the package. After the build is complete the raw stdout/stderr is analysed for known error/success patterns, then all is pushed back to the server which will pipe it straight into mongo.

The next steps are

- getting feedback
- add/remove stuff to this list and prioritize
- add reporting in the server
- writing an api
- a web-app to poke around the dataset
- fix some of the failing builds due to missing library dependency
- adding dmd nightly (which was the whole purpose)
- notifications
- track memory consumption during build (so we can push heavy builds only to heavy workers)
- windows/os-x workers
- probably a lot more

## Running a Dubster Worker

First of all, do a `docker pull skoppe/dubster-dub` and `docker pull skoppe/dubster-digger` .

Create a data container. Dubster will fire off additional containers and needs a way to share data between them.

`docker create -v /gen --name dubsterdata skoppe/dubster /bin/true`

(Note to self: `/gen/dub-cache` must explicitly be created. Find nice solution.)

Then start the container:

`docker run -d --volumes-from dubsterdata --name dubsterworker -e "DOCKER_HOST=http://172.17.0.1:2375" skoppe/dubster --worker --serverHost=https://ghozadab.skoppe.nl --memory=2147483648`

Note:

The worker needs a docker host that listens on a tcp port for http requests. `/var/run/docker.sock` is currently not supported. Try to start the docker daemon with `-H tcp://172.17.0.1:2375`.

(TODO: This is a bit hackish. Improve)

## Deploy your own Dubster Server

Note: don't just copy and paste these commands in your shell, adjust them according to your needs.

### mongo

`docker create -v /mongodata --name mongodata mongo /bin/bash -c "echo Started mongo data container"`

`docker run --volumes-from mongodata -p 27017 --name mongoserver -d mongo`

### nginx-proxy

Place a file `default` with `client_max_body_size 20m;` as content somewhere (e.g. `/root/nginx.conf/default`)

Note: adjust `/root/letscerts` to your liking

`docker run -d -p 80:80 -p 443:443 --name nginx-proxy -v /root/letscerts:/etc/nginx/certs:ro -v /usr/share/nginx/html -v /var/run/docker.sock:/tmp/docker.sock:ro -v /root/nginx.conf:/etc/nginx/vhost.d jwilder/nginx-proxy`

### letsencrypt-nginx-proxy-companion

`docker run -d -v /root/letscerts:/etc/nginx/certs:rw --volumes-from nginx-proxy -v /var/run/docker.sock:/var/run/docker.sock:ro jrcs/letsencrypt-nginx-proxy-companion`

Upon starting it will first setup keys etc. It might take 5 min before it will correctly route and all that.

### dubster

Note: Use your own host and email :)

`docker run -d --name dubsterserver -e "VIRTUAL_HOST=some.public.host" -e "LETSENCRYPT_HOST=some.public.host" -e "LETSENCRYPT_EMAIL=e@ma.il" --link mongoserver:mongo -e "MONGO_DB_NAME=dubby" skoppe/dubster --server`

## Development

### CI

Wercker CI will build and push a new image to docker hub on each git push. (TODO: isolate docker hub push only to master branch)

If you want to fork and have your own, you need to setup wercker (or other) and adjust the container names appropriately.
