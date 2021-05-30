package VV::Framework::VLoop;

use strict;
use warnings;

use Scalar::Util qw(weaken reftype);
use curry::weak;

=head1 NAME

    VV::Framework::VLoop

=head1 SYNOPSIS

    use VV::Framework::VLoop;

    # Will use $VLOOP_MODE = 'calling'
    my $vloop = VV::Framework::VLoop->new(0);
    # Will use $VLOOP_MODE = 'passing'
    my $vloop = VV::Framework::VLoop->new(1);
    # Use either ^

    $vloop->add('function_1', sub{
          #
          # With $VLOOP_MODE = 'calling';
          #
          my ($storage, $vlast) = @_;

          # Logic goes here.

          # Any control can be implemented to call &$vlast
          my $call_count = $storage->{calls_count}++;
          # Call this function_1 10 times then stop
          $vlast->() if $call_count == 10;

          # If vlast is not called VLoop will continue calling next vhead
    });

    $vloop->add('function_2', sub{
          #
          # With $VLOOP_MODE = 'passing';
          #
          my ($storage, $vlast, $vnext) = @_;

          # Logic goes here.

          # Any control can be implemented to call &$vlast
          my $call_count = $storage->{calls_count}++;
          # Call this function_1 10 times then stop
          goto &$vlast if $call_count == 10;

          # Needed in order to invoke next vhead
          goto &$vnext

    });

    $vloop->vlooper( sub {
          my $results = shift;

          for my $r (@$results) {
                print "Results from: $r->{name}\n";
                for (keys $r->{storage}->%*){
                    print "$_ => $r->{storage}{$_}\n";
                }
                print "--------------------\n";
          }
    });

=head1 DESCRIPTION

 Mian loop class
 Continuously calls added functions, until one of them calls supplied $vlast->() which will cause VLoop to stop and call passed VLast function giving it last results for each function.
 Added functions will be pushed to queue, where we constantly rotate through.
 Inspired by your memory leak questions.


=cut


# Controls whether VLoop flow invokes methods by calling(default), or by passing,
our $VLOOP_MODE;
# Controls our maximum call count, ONLY in passing mode.
our $MAX_PASSING = 1000;

sub new {
    my $vloop = shift;
    $VLOOP_MODE =   shift ? 'passing' : 'calling';

    return bless { queue => [], last => 0 }, $vloop;
}

# Determines when a running loop will come to an end.
sub last {
    my ( $vloop, $last ) = @_;
    $vloop->{last} = $last if defined $last;
    return $vloop->{last};
}

# Called to run the current configured queue
sub run {
    my $vloop = shift;

    # To add more controls, before actually invoking.
    $vloop->invoke(@_);
}

# Calls the current head function in queue.
sub invoke {
    my $vloop = shift;

    my $vhead = $vloop->vhead;



    if ($VLOOP_MODE eq 'calling') {
        # returning style where, we need to invoke next ourselves.
        # This has more natural flow to perl as control is returned here after every call.
        # This can run indefinitely without any memory leak.
        # There is no need for weaken here.
        #
        $vhead->{v}->( $vhead->{storage}, $vloop->finish );
    }
    elsif ($VLOOP_MODE eq 'passing') {
        # Continuation style where we will be passing C<&$vnext> which will invoke the next C<&$head> in queue
        #
        # Due to how perl works, recursion is limited here.
        # As even with calling `goto`, nested stacks in memory are still being created without full destruction on every iteration.
        # It never really fully transition to goto &$vnext without leaving traces behind.
        # I tried with different version of weakening. but still memory leak occurs if left to run till infinity
        #
        # use curry;
        # goto $vloop->$curry::weak($vloop->{vlast}, $vloop->{queue})->() if $vloop->last;
        # goto $vloop->$curry::weak(
        #     $vhead->{v}, $vhead->{storage},
        #     $vloop->finish,
        #     $vloop->vnext
        # )->() unless $vloop->{last};
        #
        # maybe a little ambiguous ref weakening here
        # but to me it makes more sense to weaken here,  as not to increase ref count.
        # and end closures cleanly.
        # You have to keep in mind that this is designed to run to an end using C<&$last>
        # It should not run indefinitely.
        #

        @_ = ($vhead->{storage}, $vloop->finish, $vloop->vnext);
        goto &{$vhead->{v}};
    }
}

# Adds a given function C<$v> to queue
# Name must be passed, in order for function to be tagged with
sub add {
    my ( $vloop, $name, $v ) = @_;

    # Will hold each process($v) return.
    # to be supplied again to process on every invoke.
    my $storage = {};

    push @{ $vloop->{queue} },
      { name => $name, v => $v, storage => $storage };
}

# Returns the current first element in queue
# will move head to the end of queue after calling.
sub vhead {
    my $vloop = shift;

    my $vhead = shift @{ $vloop->{queue} };
    push @{ $vloop->{queue} }, $vhead;
    return $vhead;
}

# Used only in `passing` VLoop Mode
# calling invoke causing next head to be called.
sub vnext {
    my $vloop = shift;

    # $MAX_PASSING will prevent it from endless recursion in case C<&$vlast> never called by any C<&$v>
    return $vloop->finish if ++${$vloop->{CALL_IDX}} >= $MAX_PASSING;
    return sub {$vloop->invoke};
}

# last function to be called, in order to capture final results.
# better to be supplied depending on added functions logic.
sub vlast {
    my $vloop = shift;
    return $vloop->{vlast} // sub {
    my $result = shift;

    warn "It is better to define  your own  VLast";

    # Since generic for any added C<&$V> storage
    use Data::Dumper;
    print "Result: " . Dumper($result);
    # Exit is needed when passing Mode, because it would be called using goto
    exit if $VLOOP_MODE eq 'passing';
}
}

# Called to mark loop stop, and to call provided C<&$vlast> passing to it the current queue stack.
sub finish {
    my $vloop = shift;

    return sub {
    $vloop->{last} = 1; $vloop->{vlast}->($vloop->{queue});}
}

# Main VLoop enabling  mechanism
# Call to start VLoop work
# Accepts a sub for VLast to be called when VLoop finishes
sub vlooper {
    my ( $vloop, $vlast ) = @_;
    $vloop->{vlast} = $vlast if reftype($vlast) eq 'CODE';
    if ($VLOOP_MODE eq 'calling') {
        # Continuously run VLoop
        while ( $vloop->last == 0 ) { $vloop->run(); }
    } elsif ($VLOOP_MODE eq 'passing') {
        # Let the continuation magically happen
        $vloop->run();
    }

    # Reset VLoop after finish
    $vloop->{last} = 0;

}
1;

=example_run_and_output

STDOUT->autoflush(1);

# Getopt strictly to make script using easier.
use Getopt::Long;
use Time::HiRes qw(gettimeofday);
use Data::Dumper;

STDOUT->autoflush(1);

GetOptions(
    'u|host=s'      => \( my $host    = 'www.google.com' ),
    'p|path=s'      => \( my $path    = '' ),
    'q|query=s%'    => \( my $query   = {} ),
    't|timeout=i'   => \( my $timeout = 10 ),
    'm|loop-mode=i' => \(my $loop_mode = 0),
    'h|help'        => \my $help,
);

my $show_help = $help;
die <<"EOF" if ($show_help);
usage: $0 OPTIONS
These options are available:
  -u, --host         hostname you want to request. (default: www.google.com)
  -p, --path         URI path you want. (default: )
  -q, --query        query parameters you'd like to pass.
  -t, --timeout      time in seconds for request timeout limit (default: 10)
  -m. --loop-mode    1 or 0 this  will control C<VLOOP_MODE> (1: passing, 0: calling) default( 0: calling)
  -h, --help         Show this message.
EOF

my $vloop = VV::Framework::VLoop->new($loop_mode);

$vloop->add(
    'keep_me_busy',
    sub {
        my ( $storage, $vlast, $vnext ) = @_;

        push @{ $storage->{dummy_values} }, int rand(100);
        $storage->{calls}++;

        # never go to last here
        # as we want it to keep adding as long as the other function still running.
        # keep adding as long as running.

        goto &$vnext if $VV::Framework::VLoop::VLOOP_MODE eq 'passing';
    }
);

$vloop->add(
    'async_request',
    sub {
        my ( $storage, $vlast, $vnext ) = @_;

        my $my_s = $storage->{my_s} //= VV::Framework::Loop::Socket->new;
        $my_s->http_get( $host, $path, $query, $timeout );
        $storage->{response} = $my_s->response;
        my $response = $storage->{response} //= $my_s->response;
        $storage->{$_} = $response->{$_} for keys %$response;

        # We will only stop looping once the request is done.
        $vlast->() if defined $response->{done};

        goto &$vnext if $VV::Framework::VLoop::VLOOP_MODE eq 'passing';

    }
);

$vloop->vlooper(
    sub {
        my $result = shift;

          for my $r (@$result) {
              print "Results from: $r->{name}\n";
              if ($r->{name} eq 'keep_me_busy'){
                  print "Total Call Count = $r->{storage}{calls} | ";
                  print "dummy_values added = " . scalar @{$r->{storage}{dummy_values}}. " | ";
                  print "values: ";
                  print "$_ " for @{$r->{storage}{dummy_values}};
                  print "\n";

              } elsif ( $r->{name} eq 'async_request') {
                  $r->{storage}{content_length} = 'Not Set' unless $r->{storage}{content_length};
                  print "Host: $r->{storage}{host} | Protocol: $r->{storage}{protocol} | Status: $r->{storage}{status} | Code: $r->{storage}{code} | Content-Length: $r->{storage}{content_length}\n";
                  print "Time taken for request: ". (gettimeofday - $r->{storage}{time_called}) . " Seconds\n";


              }
          }
        exit if $VV::Framework::VLoop::VLOOP_MODE eq 'passing';
    }
);
1;



root@87e6a27eb1f4:/app# perl t/t8.pl -u www.google.com -p search -q q=abc -q n=ss -t 10 -m 0
Results from: keep_me_busy
Total Call Count = 209 | dummy_values added = 209 | values: 44 80 62 86 83 59 91 38 93 25 28 41 35 71 32 29 47 45 59 60 89 89 13 73 46 54 79 78 29 25 24 99 1 91 69 4 6 11 17 39 57 71 4 61 12 53 69 60 50 7 42 31 46 36 28 43 52 27 36 70 96 61 96 6 22 33 6 92 67 1 69 82 19 91 62 78 90 94 87 11 1 44 35 7 40 40 16 23 85 12 52 88 60 58 71 79 88 23 16 82 83 74 99 25 73 33 56 30 83 44 6 31 86 41 35 1 53 91 28 78 39 70 89 98 57 36 88 60 32 80 85 91 20 10 37 98 73 22 24 51 61 14 70 56 53 72 62 0 85 52 82 77 6 87 57 26 62 79 52 65 40 36 93 30 98 63 44 87 83 78 25 25 25 73 88 53 55 45 25 30 86 76 10 8 64 88 88 75 68 68 15 71 14 40 55 29 13 81 32 92 75 35 7 79 57 37 7 60 10
Results from: async_request
Host: www.google.com | Protocol: HTTP/1.0 | Status: OK | Code: 200 | Content-Length: Not Set
Time taken for request: 0.539005041122437 Seconds

root@87e6a27eb1f4:/app# perl t/t8.pl -u www.crazypanda.ru -p search -q q=abc -q n=ss -t 10 -m 1
Results from: keep_me_busy
Total Call Count = 166 | dummy_values added = 166 | values: 85 65 39 21 93 26 82 27 11 86 39 9 0 21 73 28 96 64 10 29 83 20 18 62 73 89 10 30 25 45 5 10 97 10 84 63 2 79 41 86 89 2 37 74 92 47 2 27 86 37 68 21 3 85 1 57 12 64 62 92 42 50 8 35 75 69 72 14 48 90 59 57 50 79 67 15 41 67 94 22 80 25 14 26 94 11 62 97 58 7 36 21 52 58 80 74 14 22 97 57 53 48 78 63 34 2 77 59 21 74 32 94 94 77 36 37 6 86 37 87 68 18 29 3 14 91 11 76 96 56 75 19 11 84 4 56 76 42 83 88 93 34 3 62 39 37 25 78 36 73 5 95 29 33 69 39 59 34 42 20 83 77 0 73 7 7
Results from: async_request
Host: www.crazypanda.ru | Protocol: HTTP/1.1 | Status: Moved Temporarily | Code: 302 | Content-Length: 154
Time taken for request: 0.459303855895996 Seconds

root@87e6a27eb1f4:/app# perl tcp.pl -u www.gdogle.com -p search -q q=abc -q n=ss -t 4
Connecting at tcp.pl line 332.
Results from: keep_me_busy
Total Call Count = 1209 | dummy_values added = 1209 | values: <removed_for_better_readness>
Results from: async_request
Host: www.gdogle.com | Protocol:  | Status: Timout | Code: 408 | Content-Length: Not Set
Time taken for request: 4.01037502288818 Seconds

=end
