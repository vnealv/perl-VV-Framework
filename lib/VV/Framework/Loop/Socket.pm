package VV::Framework::Loop::Socket;

use strict;
use warnings;

use Linux::Epoll;
use Socket qw(inet_aton);
use IO::Socket qw(AF_INET SOCK_STREAM pack_sockaddr_in);
use IO::Epoll;
use Time::HiRes qw(gettimeofday);

sub new {
    my ( $class, %args ) = @_;

    my $self = bless \%args, $class;
    $self->{response} //= {
        code           => 0,
        content_length => 0,
        status         => '',
        protocol       => '',
        host           => '',
        lines          => [],
        time_called    => 0
    };
    $self->{epoll} = Linux::Epoll->new();
    return $self;
}
sub response  { shift->{response}}
sub my_socket { shift->{my_socket} }
sub epoll_fd     { shift->{epoll_fd} }


# http_get($host, $path, $query, $timeout)
sub http_get {
    my ( $self, $host, $path, $query, $timeout ) = @_;

    # set our timeout
    # for our implemented timeout
    $self->{response}{time_called} = gettimeofday unless $self->{response}{time_called};
    if(gettimeofday - $self->{response}{time_called} >= $timeout){
            $self->{response}->{code}   = 408;
            $self->{response}->{status} = 'Timout';
            $self->{response}->{done} = 1;
    }


    # Process response line if we already got them.
    $self->process_response() if defined $self->{response}{lines} && scalar @{$self->{response}{lines}} > 0;

    my $port = 80;
    my $address =  pack_sockaddr_in( $port, inet_aton($host) ) // die 'Undefined address';
    $self->{response}->{host} = $host;

    my $socket = $self->{my_socket} //= do {
        my $socket=new IO::Socket::INET (
            Proto => 'tcp',
            Type => SOCK_STREAM,
            Blocking => 0,
            # Seems like setting timeout will make it blocking
            # Timeout => $timeout,
        );
        if(!$socket) {
            my $e = $@;
            print "Could not create socket: $e\n";
        }
        $socket->bind($address);

        $self->{first} = 1;
        $socket;
    };
    # Just to gain more iterations
    if ($self->{fitst}) {
        $self->{first} = 0;
        return;
    }

    # disable write buffering on filehanndle.
    $socket->autoflush(1);

    my $epfd = $self->{epoll_fd} // epoll_create(1);
    if ($self->{second}) {
        $self->{second} = 0;
        return;
    }

    # Choose the needed EPOLL flags
    if ($self->response->{status} eq 'PENDING') {
        epoll_ctl($epfd, EPOLL_CTL_ADD, $socket->fileno, EPOLLIN | EPOLLHUP | EPOLLERR) >= 0 || die "epoll_ctl: $!\n";
    } else {
        epoll_ctl($epfd, EPOLL_CTL_ADD, $socket->fileno, EPOLLIN | EPOLLOUT | EPOLLHUP | EPOLLERR) >= 0 || die "epoll_ctl: $!\n";
    }

    # Wait for at least 1 event for maximum 1 microsecond
    my $events = epoll_wait($epfd, 1, 1);

    # Not that we will get multiple events
    # but to be on the safe side.
    for my $ev (@$events) {
        # make sure event is for our socket handler
        if ($ev->[0] == fileno($socket)) {

            # Looks like its two signals EPOLLHUP EPOLLOUT
            if ($ev->[1] == 20) {
                warn "Connecting";
                $socket->connect($address);
                return;

            } elsif ($ev->[1] == EPOLLOUT) {
                # Connection established and socket ready to write to.

                my $query_string = join('&', map { "$_=$query->{$_}" } keys %$query);
                $path = join('?', $path, $query_string) if $query_string;
                # Minimal HTTP request header
                print $socket "GET /$path HTTP/1.0\n";
                print $socket "Host: $host\n\n";
                $self->{response}->{status} = 'PENDING';
                return;
            } elsif ($ev->[1] == EPOLLIN) {
                # We got response, save it for processing.
                @{$self->{response}->{lines}} = <$socket>;
                # Close epoll & Socket
                POSIX::close($epfd);

            }
        }
    }

    return;
}

sub process_response {
    my $self =shift;

    my $size  = scalar @{$self->{response}{lines}};
    my $line = shift @{$self->{response}{lines}};
    # Status line
    unless ( $self->{response}->{code} ) {
        # remove any new lines.
        $line =~ s/[\n\r]//g;
        @{ $self->{response} }{qw(protocol code status)} =( split ' ', $line, 3 );
    }
    # get Content-Length
    $self->{response}->{content_length} = ($line =~ /^Content-Length:\s*(\d+)/ )[0] unless $self->{response}->{content_length};

    # Read all response to gain more iterations.
    # This means that this was the last line
    if($size ==1 ) {
        alarm(0);
        $self->{response}->{done} = 1;
    }
    return;
}

1;
