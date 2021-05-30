package Service::Coffee;

use Object::Pad;

class Service::Coffee extends IO::Async::Notifier;

use Future::AsyncAwait;
use Log::Any qw($log);
use Syntax::Keyword::Try;
use JSON::MaybeUTF8 qw(:v1);
use Future::Utils qw( fmap_void );
use Time::Moment;

has $vv;
has $storage;
has $fields;

BUILD (%args) {
    $fields = {
        user => {
            mandatory => 1,
            entity    => 1,
        },
        machine => {
            mandatory => 1,
            entity    => 1,
        },
        timestamp => {
            isa => 'Time::Moment', # some type casting can be implemented
        },
    };
}

async method start ($api, $vv_storage, $vv_mngr) {
    warn "Service started";
    $vv = $api;
    $storage = $vv_storage;
}

async method buy ($message) {
    my $msg_as_hash = $message->as_hash;

    # Need to move this to VV::Framework::Message class
    my $request = decode_json_utf8($msg_as_hash->{args});
    $log->warnf('GOT Request: %s', $request);

    # Only accept GET or PUT request
    if ( $request->{type} eq 'GET' or $request->{type} eq 'PUT' ) {
        # Parse arguments and parameters and accept them in various ways.
        my %args;
        my @param = $request->{param}->%*;
        @args{qw(user machine)} = @param;
        #@args{keys $request->{args}->%*} = values $request->{args}->%*;
        # in our case we strictrly want timestamp only
        try {
            $args{timestamp} = Time::Moment->from_string($request->{args}{timestamp}) if exists $request->{args}{timestamp};
        } catch ($e) {
            return {error => {text => 'Invalid timestamp format', code => 400 } };
        }
        # set timestamp if not supplied.
        $args{timestamp} = Time::Moment->now unless exists $args{timestamp};
        $log->warnf('ARGS: %s', \%args);

        return {error => {text => 'Missing Argument. Must supply user, machine', code => 400 } }
            if grep { ! exists $args{$_} } keys $fields->%*;


        # Need to add more validation
        # also its better if timestamp saved as epoch
        $args{timestamp} = $args{timestamp}->epoch;
        # Get entities details:
        # should be converted to fmap instead of for
        for my $entity (grep { exists $fields->{$_}{entity}} keys $fields->%*) {
            my %data = await $storage->record_get($entity, $args{$entity}, $entity);
            # Only if found
            delete $data{id};
            if ( grep { defined } values %data ) {
                $args{$entity.'_'.$_} = $data{$_} for keys %data;
                # since we have it all added
                $args{$entity.'_id'} = delete $args{$entity};
            } else {
                return {error => {text => 'Invalid User or Machine does not exist', code => 400 } };
            }
        }
        my $id = await $storage->record_add('coffee', %args);
        return {id => $id};
    } else {
        return {error => {text => 'Wrong request METHOD please use GET or PUT for this resource', code => 400 } };
    }
}

1;
