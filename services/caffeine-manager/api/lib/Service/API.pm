package Service::API;

use Object::Pad;

class Service::API extends IO::Async::Notifier;

use Future::AsyncAwait;
use Net::Async::HTTP::Server;
use HTTP::Response;

has $vv;

async method start($api) {
    warn "Service started";
    $vv = $api;
    await $self->re;

    my $httpserver = Net::Async::HTTP::Server->new(
   on_request => sub {
      my $self = shift;
      my ( $req ) = @_;
 
      my $response = HTTP::Response->new( 200 );
      $response->add_content( "Hello, world!\n" );
      $response->content_type( "text/plain" );
      $response->content_length( length $response->content );
 
      $req->respond( $response );
   },
);
 
$self->add_child( $httpserver );
 
await $httpserver->listen(
   addr => { family => "inet6", socktype => "stream", port => 8080 },
);
}


async method test ($message) {
    warn "I was called ". $message;

    return {passing => 1};
}

async method re () {
    my $ss = await $vv->call_rpc('Service::API', timeout => 8, method => 'test', param => 2, args => 2);
    warn "$ss ";
}
1;
