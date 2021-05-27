package Service::Machine;

use Object::Pad;

class Service::Machine extends IO::Async::Notifier;

use Future::AsyncAwait;

has $vv;

async method start($api) {
    warn "Service started";
    $vv = $api;
}

1;
