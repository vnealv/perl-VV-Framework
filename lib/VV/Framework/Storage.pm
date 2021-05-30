package VV::Framework::Storage;

use Object::Pad;

class VV::Framework::Storage extends IO::Async::Notifier;

use Future::AsyncAwait;
use Log::Any qw($log);
use Syntax::Keyword::Try;
use Future::Utils qw( fmap_concat fmap_void );

use curry;

has $redis;
has $transport;
has $service_name;
has $prefix;
has $r_prefix;
has $l_prefix;

method configure_unknown (%args) {
    $service_name = $args{service_name};
    $transport = $args{transport};
    # Acquire dedicated redis connection for Storage
    $redis = $transport->redis_instance;

    $prefix = sub {
        my ($key, $service) = @_;
        return $service ? 
            join '_', join('::', (split('::', $service_name))[0], $service), $key :
            join '_', $service_name, $key;

        };
    $r_prefix = sub {
        my ($key, $service) = @_;
        return join '-', $prefix->($key, $service), 'RECORD';
    };
    $l_prefix = sub {
        my ($key, $service) = @_;
        return join '-', $prefix->($key, $service), 'LIST';
    };
}

async method start() {
    await $transport->instance_connect($redis);
}

method redis() {
    #   await $self->start;
   return $redis;
}


# ################################# #
# Two types of Storage:             #
# --------------------------------- #
# State                             #
#   $pre . KEY => VALUE             #
# --------------------------------- #
# Store                             #
#   $pre . KEY => [ { K => V }, ]   #
# ################################# #

async method state_get ($key, $service = '') {

    await $redis->get($prefix->($key, $service));
}

async method state_set ($key, $value) {
    # Set only to own service
    await $redis->set($prefix->($key) => $value);
}

async method store_get ($key, $k, $service = '') {
    await $redis->hget($prefix->($key, $service), $k);
}

async method store_add ($key, $k, $v) {
    # Set only to own service
    await $redis->hset($prefix->($key), $k, $v);
}

# ######################################### #
# Record                                    #
# ----------------------------------------- #
# A collection of C<Stores> governed by     #
# two C<State>s as its C<K> and C<Fields>;  #
# Resembling an ID to this record, which    #
# entirly with its C<Fields> and C<V>       #
# makes up a table.                         #
# ----------------------------------------- #
#                                           #
#   # Always pointing to latest with it     #
#   # being incremental                     #
#   $pre . KEY => ID,                       #
#   $pre . KEY_FIELDS => [F1, F2]           #
#   [                                       #
#     $pre . F1 => [ {ID => V}, ],          #
#   ]                                       #
#                                           #
# ######################################### #

async method record_add ($key, %record) {
    my $id = await $self->new_id($key);
    $log->debugf('Got record to add | KEY: %s | new_ID: %s | record: %s',  $key, $id, \%record);
    try{
        await &fmap_void(
            $self->$curry::weak(async method ($field) {
                $log->warnf('Setting Record field | Key: %s | ID: %s | V: %s | record: %s', $r_prefix->($field), $id, $record{$field}, \%record);
                await $self->redis->hset($r_prefix->($field), $id, $record{$field});
            }),
            foreach => [keys %record], concurrent => 8,
        );
    } catch ($e) {
        $log->warnf("Failed to add record: %s | error: %s", \%record, $e);
    }
    # Update field list.
    my $fields_key = $r_prefix->($key.'-F');
    # Can be cached.
    my $fields_exists = await $redis->llen($fields_key);
    $log->debugf('KEY FIELD length: %s',  $fields_exists);
    unless ($fields_exists) {
        &fmap_void(
            $self->$curry::weak(async method ($field) {
                await $self->redis->rpush($fields_key, $field);
            }),
            foreach => [keys %record], concurrent => 8
        );
    }
    return $id;

}

async method record_get ($key, $id, $service = '') {
    my $fields = await $redis->lrange($r_prefix->($key.'-F'), 0, -1);

    $log->warnf('Fields to get: %s', $fields);
    $id = $self->latest_id($key, $service) if $id == 0;
    my %record = await &fmap_concat(
        $self->$curry::weak(async method ($field) {
            my $value = await $self->redis->hget($r_prefix->($field), $id);
            $log->warnf('HGET %s:  %s | %s', $r_prefix->($field), $id, $value);
            return ( $field => $value );
        }),
        foreach => $fields, concurrent => 8
    );
    $record{id} = $id;
    $log->warnf('RECORD: %s', \%record);
    return %record;

}

# ID operations

async method new_id ($key) {
    # Only own service
    await $redis->incr($r_prefix->($key.'-ID'));
}

async method latest_id ($key, $service) {
    await $redis->get($r_prefix->($key.'-ID', $service));
}

# ########################### #
# Unique Lists                #
# --------------------------- #
# Mainly RPUSH and LRANGE     #
# ########################### #

async method list_push ($key, $v) {
    await $redis->rpush($l_prefix->($key), $v);
}

async method list_get ($key, $service = '', $r1 = 0, $r2 = -1) {
    await $redis->lrange($l_prefix->($key, $service), $r1, $r2);
}
1;
