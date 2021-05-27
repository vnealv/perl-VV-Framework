package Service::Coffee;

use Object::Pad;

class Service::Coffee extends IO::Async::Notifier;

use Future::AsyncAwait;

has $vv;

async method start($api) {
    warn "Service started";
    $vv = $api;
}

1;
