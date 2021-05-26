package VV::Framework::Message::Redis;

use Object::Pad;

class VV::Framework::Message::Redis;

use Log::Any qw($log);
use Syntax::Keyword::Try;
use JSON::MaybeUTF8 qw(:v1);

has $rpc;
has $message_id;
has $transport_id;
has $who;
has $deadline;

has $args;
has $stash;
has $response;
has $trace;


method message_id { $message_id }

method transport_id { $transport_id };

method rpc { $rpc }

method who { $who }

method deadline { $deadline }

method args { $args }

method response :lvalue { $response }

method stash { $stash }

method trace { $trace }

BUILD(%message) {
    $rpc          = $message{rpc};
    $who          = $message{who};
    $message_id   = $message{message_id};
    $transport_id = $message{transport_id};
    $deadline     = $message{deadline} || time + 30;
    $args         = $message{args} || {};
    $response     = $message{response} || {};
    $stash        = $message{stash} || {};
    $trace        = $message{trace} || {};
}

method as_hash () {
    my $data =  {
        rpc => $rpc,
        who => $who,
        message_id => $message_id,
        deadline => $deadline,
    };

    $self->apply_encoding($data, 'utf8');

    return $data;

}

method as_json () {
        my $data = {
            rpc        => $rpc,
            message_id => $message_id,
            who        => $who,
            deadline   => $deadline,
        };

        $self->apply_encoding($data, 'text');
        return encode_json_utf8($data);
}

sub from_hash (%hash) {
    is_valid(\%hash);
    apply_decoding(\%hash, 'utf8');

    return VV::Framework::Message::Redis->new(%hash);
}

sub from_json ($json) {
    my $raw_message = decode_json_utf8($json);
    is_valid($raw_message);
    apply_decoding($raw_message, 'text');

    return VV::Framework::Message::Redis->new($raw_message->%*);
}

sub is_valid ($message) {
    for my $field (qw(rpc message_id who deadline args)) {
        $log->warnf('Not a valid message | "%s is requried"', $field) unless exists $message->{$field};
    }
}

method apply_encoding ($data, $encoding) {
    my $encode = $encoding eq 'text' ? \&encode_json_text : \&encode_json_utf8;
    try {
        for my $field (qw(args response stash trace)) {
            $data->{$field} = $encode->($self->$field);
        }
    } catch($e) {
        $log->warnf('Error encoding: %s', $e);
    }
}

sub apply_decoding ($data, $encoding) {
    my $decode = $encoding eq 'text' ? \&decode_json_text : \&decode_json_utf8;
    try {
        for my $field (qw(args response stash trace)) {
            $data->{$field} = $decode->($data->{$field}) if $data->{$field};
        }
    } catch ($e) {
        $log->warnf('Error decoding: %s', $e);
    }
}

1;
