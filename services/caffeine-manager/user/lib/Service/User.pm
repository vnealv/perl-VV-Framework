package Service::User;

use Object::Pad;

class Service::User extends IO::Async::Notifier;

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
        login => {
            mandatory => 1,
            unique    => 1,
        },
        password => {
            mandatory => 1,
            hashed    => 1, # add support for hashing
        },
        email => {
            mandatory => 1,
            unique    => 1,
        },
    };
}

async method start ($api, $vv_storage, $vv_mngr) {
    warn "Service started";
    $vv = $api;
    $storage = $vv_storage;
}

async method request ($message) {
    my $msg_as_hash = $message->as_hash;

    # Need to move this to VV::Framework::Message class
    my $request = decode_json_utf8($msg_as_hash->{args});
    $log->warnf('GOT Request: %s', $request);

    # Only accept PUT request
    if ( $request->{type} eq 'PUT' ) {
        my %args = $request->{args}->%*;
        return {error => {text => 'Missing Argument. Must supply login, password, email', code => 400 } }
            if grep { ! exists $args{$_} } keys $fields->%*;

        my %unique_values;
        # should be converted to fmap instead of for
        for my $unique_field (grep { exists $fields->{$_}{unique}} keys $fields->%*) {
            $unique_values{$unique_field} = await $storage->list_get($unique_field);
            return {error => {text => 'User already exists', code => 400 } } if grep /^$args{$unique_field}$/, $unique_values{$unique_field}->@*;
        }
        $log->debugf('Unique values %s', \%unique_values);

        # Need to add more validation
        my $id = await $storage->record_add('user', %args);
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
