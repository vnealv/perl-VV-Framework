package VV::Framework::Transport::Redis;

use Object::Pad;

class VV::Framework::Transport::Redis extends IO::Async::Notifier;

use Log::Any qw($log);
use Syntax::Keyword::Try;
use Future::AsyncAwait;
use Net::Async::Redis;
use Net::Async::Redis::Cluster;
use Ryu::Async;
use VV::Framework::Message::Redis;
use VV::Framework::Util qw(whoami);
use curry;

has $redis_uri;
has $redis;
has $use_cluster;
has $service_name;
has $ryu;
has $group_name;
has $wait_time;
has $batch_count;
has $subscription_sink;
has $current_id;

method configure (%args) {
    $redis_uri //= (URI->new(delete $args{redis_uri}) || die 'need a redis_uri');
    $use_cluster //= (delete $args{cluster} || 0);
    $service_name //= (delete $args{service_name} || die 'need service_name');
    $group_name = 'processors';
    $wait_time = 15000;
    $batch_count = 50;
    $current_id = 0;
    $self->next::method(%args);
}


method _add_to_loop($loop) {
    $log->tracef('Adding %s to loop, %s | %s | %s', ref $self, $redis_uri, $redis_uri->port, $use_cluster);
    $self->redis;
    $self->add_child($ryu = Ryu::Async->new);

    $self->next::method($loop);
}

method redis () {
    return $redis //= $self->redis_instance;
}
method redis_instance () {
    my $instance;
    if($use_cluster) {
        $instance = Net::Async::Redis::Cluster->new(
            client_side_cache_size => 0, # We can just set it to zero for now
        );
    } else {
        $instance = Net::Async::Redis->new(
            host => $redis_uri->host,
            port => $redis_uri->port,
            client_side_cache_size => 0,
        );
    }

    $self->add_child(
        $instance
    );
    
    return $instance;
}

async method instance_connect ($instance) {

    $log->tracef('Connecting to Redis | %s', $redis);
    if ($use_cluster) {
        await $instance->bootstrap(
            host => $redis_uri->host,
            port => $redis_uri->port,
        );
    } else {
        await $instance->connect;
    }
}

async method start() {

    await $self->instance_connect($redis);
    $self->requests_subscription->retain;

}

async method requests_subscription () {
    $subscription_sink = $ryu->sink(label => "requests_subscription:$service_name");
    await $self->create_stream($service_name);

    my $dedicated_redis = $self->redis_instance;
    while (1) {
        await $self->instance_connect($dedicated_redis);

        my @items = await $self->read_from_stream($dedicated_redis, $service_name);

        for my $item (@items) {
            push $item->{data}->@*, ('transport_id', $item->{id});
            try {
                my $message = VV::Framework::Message::Redis::from_hash($item->{data}->@*);
                $log->debugf('Received RPC request as %s', $message);
                $subscription_sink->emit($message);
            } catch ($error) {
                $log->tracef("error while parsing the incoming messages: %s", $error->message);
                await $self->drop($service_name, $item->{id});
            }
        }
    }
}

async method create_stream ($stream, $start_from = '$') {
    try {
        $log->warnf('CREATING GROUP: %s', $stream);
        await $redis->xgroup('CREATE', $stream, $group_name, $start_from, 'MKSTREAM');
    } catch ($e) {
        if($e =~ /BUSYGROUP/){
            return;
        } else {
            die $e;
        }
    }
}

async method read_from_stream ($redis_instance, $stream) {

    # require dedicated $redis_instance
    my ($delivery) = await $redis_instance->xreadgroup(
        BLOCK   => $wait_time,
        GROUP   => $group_name, whoami(),
        COUNT   => $batch_count,
        STREAMS => ($stream, '>'),
    );

    $log->tracef('Read group %s', $delivery);

    # We are strictly reading for one stream
    my $batch = $delivery->[0];
    if ($batch) {
        my  ($stream, $data) = $batch->@*;
        return map {
            my ($id, $args) = $_->@*;
            $log->tracef('Item from stream %s is ID %s and args %s', $stream, $id, $args);
            +{
                stream => $stream,
                id     => $id,
                data   => $args,
            }
        } $data->@*;
    }

    return ();
}

async method reply ($stream, $message) {
    try {
        await $self->redis->publish($message->who, $message->as_json);
        await $self->redis->xack($stream, $group_name, $message->transport_id);
    } catch ($e) {
        $log->warnf("Failed to reply to client due: %s", $e);
        return;
    }
}

async method drop ($stream, $id) {
    $log->tracef("Going to drop message: %s", $id);
    await $self->redis->xack($stream, $self->group_name, $id);
}

method next_id () {
    return $current_id++;
}

method subscription_sink () { $subscription_sink; }

1;
