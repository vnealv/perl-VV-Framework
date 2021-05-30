package Service::Stats;

use Object::Pad;

class Service::Stats extends IO::Async::Notifier;

use Future::AsyncAwait;
use Log::Any qw($log);
use Syntax::Keyword::Try;
use JSON::MaybeUTF8 qw(:v1);
use Future::Utils qw( fmap_void );
use Time::Moment;
use curry;

has $vv;
has $storage;
has $hook;
has $fields;

BUILD (%args) {
    $fields = {
        coffee => {
            isa => 'VV::Framework::Hook', # some type casting can be implemented
            has => {
                user => {
                    isa => 'VV::Framework::Service',
                },
                machine => {
                    isa => 'VV::Framework::Service',
                },
                timestamp => {
                    isa => 'VV::Framework::Service',
                },
            }
        },
        level => {
            res => '1h',
            ret => '24h',
        },
    };
}

method storage () { $storage; }
async method start ($api, $vv_storage, $vv_hook) {
    $vv = $api;
    $storage = $vv_storage;
    $hook = $vv_hook;
    await $hook->add_hook('coffee', $self->$curry::weak($self->coffee_hook));
}

method coffee_hook (@params) {
    return async sub {
        my ($self, $params) = @_;
        $log->debugf('stats coffee_hook incoming event %s', $params);
        # {machine_caffeine => 40,machine_id => 3,machine_name => "MACHINE1",timestamp => 1622389101,user_email => "ssss",user_id => 9,user_login => "NAEL",user_password => "pass"}
        delete $params->{user_password};
        await $self->storage->list_push('coffee', encode_json_utf8($params));
        await $self->storage->list_push("coffee_machine_$params->{machine_id}", encode_json_utf8($params));
        await $self->storage->list_push("coffee_user_$params->{user_id}", encode_json_utf8($params));

        # Level here is the same as coffee_user_$params->{user_id}
        # However needed here, so we can clear it every 24h
        my $level = {machine_caffeine => $params->{machine_caffeine}, user_name => $params->{user_name}, user_id => $params->{user_id}, timestamp => $params->{timestamp} };
        await $self->storage->list_push("level_$params->{user_id}", encode_json_utf8($level));
    };

}

async method coffee ($message, $entity = '') {
    my $msg_as_hash = $message->as_hash;

    # Need to move this to VV::Framework::Message class
    my $request = decode_json_utf8($msg_as_hash->{args});
    $log->debugf('GOT Request: %s', $request);

    # Only accept GET
    if ( $request->{type} eq 'GET' ) {

        my $result = [];
        my @param = $request->{param}->%*;
        my $id = shift @param if  0 + @param;
        my $key =  $entity ? join '_', 'coffee', $entity, $id : 'coffee';

        my $list = await $storage->list_get($key);
        $log->tracef('Coffee list for stats %s', $list);
        push @$result, decode_json_utf8($_) for $list->@*;

        return {result => $result, count => scalar @$result};
    } else {
        return {error => {text => 'Wrong request METHOD please use GET or PUT for this resource', code => 400 } };
    }
}

# since all are using the same return structure we can
# reuse them in this way.
async method coffee_machine ($message) {
    await $self->coffee($message, 'machine');
}

async method coffee_user ($message) {
    await $self->coffee($message, 'user');
}

async method level_user ($message) {
    my $msg_as_hash = $message->as_hash;

    # Need to move this to VV::Framework::Message class
    my $request = decode_json_utf8($msg_as_hash->{args});
    $log->debugf('GOT Request: %s', $request);

    # Only accept GET
    if ( $request->{type} eq 'GET' ) {

        my $result = [];
        my @param = $request->{param}->%*;
        my $id = shift @param if  0 + @param;
        return {error => {text => 'Need id', code => 400 } } unless $id;

        my $key = join '_', 'level', $id;

        my $list = await $storage->list_get($key);
        $log->tracef('Level list for stats %s', $list);
        push @$result, decode_json_utf8($_) for $list->@*;

        my $time_now = Time::Moment->now();
        my $window = {map {$time_now->minus_hours($_)->to_string() => {level => 0}} 1 .. 24 };
        my $level = 0;
        for my $intake (@$result) {
            # Already in ascending order.
            my $intake_time = Time::Moment->from_epoch($intake->{timestamp});
            my $diff = $intake_time->delta_hours($time_now);

            # Skip if more than 24h window
            next if $diff > 24;

            # Deal with window first.
            my $window_time = $time_now->minus_hours($diff);
            my $window_diff = $intake_time->delta_hours($window_time);
            my $window_level = $intake->{machine_caffeine} - $intake->{machine_caffeine} * ($window_diff * 0.1);
            $window->{$window_time->to_string()}{level} += $window_level;
            $window->{$window_time->to_string()}{level} = 100 if $window->{$window_time->to_string()}{level} > 100;

            # Separate real-time from window calculation
            # Linear increment where it takes 10h for current caffeine intake to be gone.
            # and max when first consumed
            $diff = 10 if $diff > 10;
            my $current_level = $intake->{machine_caffeine} - $intake->{machine_caffeine} * ($diff * 0.1);

            # Add current level to total.
            $level += $current_level;
            # Cap it to 100%
            $level = 100 if $level > 100;
        }
        return {user_id => $id, window => $window, level => $level};
    } else {
        return {error => {text => 'Wrong request METHOD please use GET or PUT for this resource', code => 400 } };
    }
}

1;
