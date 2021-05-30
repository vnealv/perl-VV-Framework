package VV::Framework::Manager;

use Object::Pad;

class VV::Framework::Manager;

use Future::AsyncAwait;
use Log::Any qw($log);
use Syntax::Keyword::Try;

use curry;

has $service;
has $transport;
has $service_name;

BUILD (%args) {
    $transport = $args{transport};
    $service   = $args{service};
    $service_name = $args{service_name};
}


async method link_requests () {
    my $request_source = $transport->subscription_sink->source;
    $request_source->map($self->$curry::weak(async method ($message) {
        try {
            $log->debugf('Received request message %s', $message->as_hash);
            my $method = $message->args->{method};
            if ( defined $method and $service->can($method) ) {
                my $response = await $service->$method($message);
                unless (exists $response->{error}) {
                    await $self->reply_success($service_name, $message, $response);
                } else {
                    await $self->reply_error($service_name, $message, $response->{error});
                }
            } else {
                $log->warnf('Error RPC method not found | message: %s', $message);
                await $self->reply_error($service_name, $message, {text => 'NotFound', code => 400});
            }
        } catch ($e) {
            $log->warnf('Error linking request: %s | message: %s', $e, $message);
            await $self->reply_error($service_name, $message, {text => $e, code => 500});
        }
    }))->resolve->completed;
}

async method reply_success ($service, $message, $response) {
    $message->response = { response => $response };
    await $transport->reply($service, $message);
}

async method reply_error ($service, $message, $error) {
    $message->response = { error => { error_code => $error->{code}, error_text => $error->{text} } };
    await $transport->reply($service, $message);
}

1;
