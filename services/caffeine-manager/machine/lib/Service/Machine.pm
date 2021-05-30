package Service::Machine;

use Object::Pad;

class Service::Machine extends IO::Async::Notifier;

use Future::AsyncAwait;
use Log::Any qw($log);
use Syntax::Keyword::Try;
use JSON::MaybeUTF8 qw(:v1);
use Future::Utils qw( fmap_void );

has $vv;
has $storage;
has $fields;

BUILD (%args) {
    $fields = {
        name => {
            mandatory => 1, # not required
            unique    => 1, # not required
        },
        caffeine => {
            mandatory => 1, # not required
        },
    };
}

async method start ($api, $vv_storage, $vv_hook) {
    $vv = $api;
    $storage = $vv_storage;
}


# Default method called is request
async method request ($message) {
    my $msg_as_hash = $message->as_hash;

    # Need to move this to VV::Framework::Message class
    my $request = decode_json_utf8($msg_as_hash->{args});
    $log->debugf('GOT Request: %s', $request);

    # Only accept PUT request
    if ( $request->{type} eq 'POST' ) {
        my %args = $request->{args}->%*;
        return {error => {text => 'Missing Argument. Must supply name, caffeine', code => 400 } }
            if grep { ! exists $args{$_} } keys $fields->%*;

        my %unique_values;
        # should be converted to fmap instead of for
        for my $unique_field (grep { exists $fields->{$_}{unique}} keys $fields->%*) {
            $unique_values{$unique_field} = await $storage->list_get($unique_field);
            return {error => {text => 'User already exists', code => 400 } } if grep /^$args{$unique_field}$/, $unique_values{$unique_field}->@*;
        }
        $log->debugf('Unique values %s', \%unique_values);

        # Need to add more validation
        my $id = await $storage->record_add('machine', %args);
        await fmap_void(
            async sub {
                my $key = shift;
                await $storage->list_push($key, $args{$key});
            }, foreach => [keys %unique_values], concurrent => 4
        );
        return {id => $id};
    } else {
        return {error => {text => 'Wrong request METHOD please use PUT for this resource', code => 400 } };
    }
}
1;
