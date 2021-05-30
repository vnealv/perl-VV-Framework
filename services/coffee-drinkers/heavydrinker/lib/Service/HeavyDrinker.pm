package Service::HeavyDrinker;

use Object::Pad;

class Service::HeavyDrinker extends IO::Async::Notifier;


use Future::AsyncAwait;
use Log::Any qw($log);
use Syntax::Keyword::Try;

use Net::Async::HTTP;
use URI;
use JSON::MaybeUTF8 qw(:v1);
use String::Random;
use Future::Utils qw( fmap_concat fmap_void );

has $api;
has $storage;
has $hook;
has $http;
has $base_url;

has $users;
has $machines;
has $factor = 4;
has $rand;

async method start ($vv_api, $vv_storage, $vv_hook) {
    $api = $vv_api;
    $base_url = 'http://caffeine-manager_api:80';

    $users = $machines = [];
    $rand = String::Random->new;

    #my $user_id = await $self->add_user({login => 'naelll', password => 'sdaa', email => 'sdfdsf'});
    #my $machine_id = await $self->add_machine({login => 'naelll', password => 'sdaa', email => 'sdfdsf'});
    #await $self->buy_coffee($user_id, $machine_id);
    #$log->warnf('ffff %s', $user_id);

    # Start with 4 users, and 4 machines.
    #   do (4 * users_count) concurrent buys.
    #   add 4 users, and 4 machines more and repeat
    while (1) {
        await fmap_void( async sub {
            try {
                my $user_hash = {login => $rand->randpattern("CccccCcCC"), password => 'pass', email => $rand->randpattern("CCCccccccc")};
                $log->infof('Adding user: %s', $user_hash);
                my $user = await $self->add_user($user_hash);
                my $user_re = decode_json_utf8($user->content); 
                my $user_id = $user_re->{response}{id}; 
                push @$users, $user_id if defined $user_id;
            
                my $machine_hash = {name => $rand->randpattern("Ccccccccc"), caffeine => $rand->randpattern("n")};
                $log->infof('Adding Machine: %s', $machine_hash);
                my $machine = await $self->add_machine($machine_hash);
                my $machine_re = decode_json_utf8($machine->content); 
                my $machine_id = $machine_re->{response}{id}; 
                push @$machines, $machine_id if defined $machine;
            } catch ($e) {
                $log->warnf('Fail %s', $e);
            }
        }, foreach => [0 .. $factor], concurrent => $factor);

        my $loop_count = $factor * @$users;
        await fmap_void( async sub {
            my $rnd_user = $users->[int rand(0+@$users) ];
            my $rnd_machine = $machines->[int rand(0+@$machines) ];
            $log->infof('Buying Coffee: user_id: %s | machine_id: %s', $rnd_user, $rnd_machine);
            my $res = await $self->buy_coffee($rnd_user, $rnd_machine);
            $log->warnf('Bought Coffee %s', decode_json_utf8($res->content));
        }, foreach => [0 .. $loop_count], concurrent => $factor);

    }
}

async method add_user ($user) {
    my $res;
    try {
        $res = await $http->do_request(uri => URI->new($base_url.'/user/request'), method => 'PUT', content => encode_json_utf8($user), content_type => 'application/json');
    } catch ($e) {
        ($res)  = $e->details;
        $log->warnf('Could not add User %s | Error: %s | content: %s', $user, $e, $res->content);
    }
    return $res;
}

async method add_machine ($machine) {
    my $res;
    try {
        $res = await $http->do_request(uri => URI->new($base_url.'/machine'), method => 'POST', content => encode_json_utf8($machine), content_type => 'application/json');
    } catch ($e) {
        ($res)  = $e->details;
        $log->warnf('Could not add Machine %s | Error: %s | content: %s', $machine, $e, $res->content);
    }
    return $res;
}

async method buy_coffee ($user, $machine) {
    my $res;
    try {
        $res = await $http->do_request(uri => URI->new(join '/', $base_url, 'coffee', 'buy', $user, $machine), method => 'PUT', content_type => 'application/json');
    } catch ($e) {
        ($res)  = $e->details;
        $log->warnf('Could not buy coffee (User: %s, Machine: %s) | Error: %s | content: %s', $user, $machine, $e, $res->content);
    }
    return $res;
}

method _add_to_loop ($loop) {
    $self->add_child(
        $http = Net::Async::HTTP->new(
            fail_on_error            => 1,
            max_connections_per_host => 2,
            pipeline                 => 1,
            max_in_flight            => 8,
            decode_content           => 1,
            timeout                  => 60,
        )
    );
}

1;
