package Service::API;

use Object::Pad;

class Service::API extends IO::Async::Notifier;

use Future::AsyncAwait;

async method start() {
    warn "Service started";
}


async method test ($message) {
    warn "I was called ". $message;

    return {passing => 1};
}
1;
