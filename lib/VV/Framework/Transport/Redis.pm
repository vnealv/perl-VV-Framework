package VV::Framework::Transport::Redis;

use Object::Pad;

class VV::Framework::Transport::Redis extends IO::Async::Notifier;

use Log::Any qw($log);
use Future::AsyncAwait;
use Net::Async::Redis;

has $redis_uri;
has $redis;
has $use_cluster;

method configure (%args) {
    $redis_uri //= (URI->new(delete $args{redis_uri}) || die 'need a redis_uri');
    $use_cluster //= (delete $args{cluster} || 0);
    $self->next::method(%args);
}


method _add_to_loop($loop) {
    $log->tracef('Adding %s to loop, %s | %s | %s', ref $self, $redis_uri, $redis_uri->port, $use_cluster);
    $self->redis_instance;

    $self->next::method($loop);
}

async method start() {
 
    $log->tracef('Connecting to Redis | %s', $redis);
    if ($use_cluster) {
        await $redis->bootstrap(
            host => $redis_uri->host,
            port => $redis_uri->port,
        );
    } else {
        await $redis->connect;
    }
}

method redis_instance () {
    unless ($redis) {
        if($use_cluster) {
            $redis = Net::Async::Redis::Cluster->new(
                client_side_cache_size => 0, # We can just set it to zero for now
            );
        } else {
            $redis = Net::Async::Redis->new(
                host => $redis_uri->host,
                port => $redis_uri->port,
                client_side_cache_size => 0,
            );
        }

        $self->add_child(
            $redis
        );
    }
    return $redis;
}

1;
