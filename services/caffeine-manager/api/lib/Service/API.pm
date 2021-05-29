package Service::API;

use Object::Pad;

class Service::API extends IO::Async::Notifier;

use Log::Any qw($log);
use Syntax::Keyword::Try;
use Future::AsyncAwait;

use Server::REST;
use Ryu::Async;
use curry;


has $vv;
has $ryu;
has $http_server;

method _add_to_loop($loop) {
    $self->add_child(
        $ryu = Ryu::Async->new()
    );
    $self->add_child(
        $http_server = Server::REST->new(listen_port => 80)
    );
}

has $s;
async method start($api) {
    $vv = $api;

    my $sink = $ryu->sink(label => "http_requests_sink");
    $s = $sink->source->map(
        $self->$curry::weak(async method ($incoming_req) {
            my $req = delete $incoming_req->{request};
            $log->debugf('Incoming request to http_requests_sink | %s', $incoming_req);
            try {
                my $service_response = await $self->request_service($incoming_req);
                if ( exists $service_response->{error} ) {
                    $http_server->reply_fail($req, $service_response->{error});
                } else {
                    $http_server->reply_success($req, $service_response);
                }
            } catch ($e) {
                $log->warnf('Outgoing failed reply to HTTP request %s', $e);
                $http_server->reply_fail($req, $e);
            }
        }
    ))->resolve->completed;

    await $http_server->start($sink);
}

async method request_service ($incoming_req) {
    # In fact hash can be passed as it is, however it is kept for clarity.
    my ($service, $method, $param, $args, $type) = @$incoming_req{qw(service method params body type)};
    return await $vv->call_rpc($service, timeout => 10, method => $method, param => $param, args => $args, type => $type);
}

async method health ($message) {
    # In here we can check on all services health
    # and report which specific API calls health checks.

    $log->infof('Message received to health: %s', $message);

    return { api_health => 'up', services_health => {'user' => 'up'} };
}

1;
