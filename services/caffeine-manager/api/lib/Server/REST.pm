package Server::REST;

use Object::Pad;

class Server::REST extends IO::Async::Notifier;


use Future::AsyncAwait;
use Syntax::Keyword::Try;
use Net::Async::HTTP::Server;
use HTTP::Response;
use JSON::MaybeUTF8 qw(:v1);
use Unicode::UTF8;
use Scalar::Util qw(refaddr blessed);

use Log::Any qw($log);

=head1 NAME

Caffeine Manager REST API Service

=head1 DESCRIPTION

Provides an HTTP interface to Caffeine Manager.

=cut

has $server;
has $listen_port;
has $active_requests;
has $service;

method configure (%args) {

    $listen_port = delete $args{listen_port} if exists $args{listen_port};
    $active_requests = {};

    return $self->next::method(%args);
}


method _add_to_loop () {
    # server for incoming requests
    $self->add_child(
        $server = Net::Async::HTTP::Server->new(
            on_request => sub {
                my ($http, $req) = @_;
                # without this we will have "lost its returning future" errors
                my $k = refaddr($req);
                $active_requests->{$k} = $self->handle_http_request($req)->on_ready(sub { delete $active_requests->{$k} });
            }));

}


async method handle_http_request ($req) {

    my ($req) = @_;
    try {
        $log->debugf('HTTP receives %s:%s', $req->path, $req->body);

        # See Net::Async::HTTP::Server for methods available here
        my ($method) = $req->path =~ qr{^/([A-Za-z]+)};
        my $query    = {$req->query_form};
        my $params   = decode_json_utf8($req->body || '{}');
        $log->tracef('Had query %s and parameters %s for method %s', $query, $params, $method);
        my $data = await handle_request(
            method => $method,
            %$query,
            %$params
        );
        my $response = HTTP::Response->new(200);
        $response->add_content(encode_json_utf8($data));
        $response->content_type("application/javascript");
        $response->content_length(length $response->content);

        $req->respond($response);
    } catch ($e) {
        $log->errorf('Failed with MT5 request - %s', $e);
        try {
            my $response = HTTP::Response->new(500);
            # If this is a properly-formatted MT5 error, we can return as JSON
            if (ref $e) {
                $e = encode_json_text($e);
                $response->content_type("application/javascript");
            } else {
                # ... but if we don't know what it is, stick to a string
                $response->content_type("text/plain");
            }

            $response->add_content(Unicode::UTF8::encode_utf8("$e"));
            $response->content_length(length $response->content);

            $req->respond($response);
        } catch ($e2) {
            $log->errorf('Failed when trying to send failure response for MT5 request - %s', $e2);
        }
    }
}

async method handle_request (%args) {
    my $method = delete $args{method};

    # Convert method from PascalCase to camel_case
    $method =~ s{(?<=[a-z])([A-Z])}{'_' . lc($1)}ge;
    $method = lc $method;

    try {
        return await $service->call( $method, %args);
    } catch ($e) {
        $log->warnf('Failed calling method %s, Error: %s', $method, $e);
    }
}

async method start () {
    
    my $listner = await $server->listen(
        addr => {
            family   => 'inet',
            socktype => 'stream',
            port     => $listen_port});
    my $port = $listner->read_handle->sockport;

    $log->debugf('HTTP REST API service is listening on port %s', $port);
    return $port;
}

1;
