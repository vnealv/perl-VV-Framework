package Service::StorageTest;

use Object::Pad;

class Service::StorageTest extends IO::Async::Notifier;

use Future::AsyncAwait;
use Log::Any qw($log);
use Syntax::Keyword::Try;
use Test::More;

has $vv;
has $storage;

async method start ($api, $vv_storage) {
    warn "Service started";
    $vv = $api;
    $storage = $vv_storage;
}

async method test($message) {

    $log->warnf('GOT MESSAGE: %s', $message);
    my $testing_rpc = await $vv->call_rpc('api', timeout => 10, method => 'health', param => {}, args => {}, type => 'GET');
    $log->warnf('Testing RPC %s', $testing_rpc);
    try {
        my %r = (nael => int rand(100), test => 'check'); 
        my $inserted_id = await $storage->record_add('testing', %r);
        $log->debugf('inserted_id: %s', $inserted_id);
        my %record = await $storage->record_get('testing', $inserted_id);
        my $id = delete $record{id};
        is_deeply(\%r, \%record, 'MATCHING');
        $record{id} = $id;
        return {success => "Hi from Coffee service", testing_rpc => $testing_rpc, storage_test => \%record};
    } catch ($e) {
        $log->warnf('Error %s', $e);
    }
}

1;
