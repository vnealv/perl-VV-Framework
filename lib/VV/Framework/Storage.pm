package VV::Framework::Storage;

use Object::Pad;

class VV::Framework::Storage;

use Future::AsyncAwait;
use Log::Any qw($log);
use Syntax::Keyword::Try;

has $redis;
has $transport;
has $service_name;

BUILD (%args) {
    $service_name = $args{service_name};
    $transport = $args{transport};
    # Acquire dedicated redis connection for Storage
    $redis = $transport->redis_instance;
}

async method start() {
    await $transport->instance_connect($redis);
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

async method state_get ($key) {

}

async method state_set ($key, $value) {

}

async method store_get ($key, $k = '') {

}

async method store_add ($key, $k, $v) {

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

}

async method record_get ($key, $id = 0) {

}

1;
