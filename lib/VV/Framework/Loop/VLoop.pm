package VV::Framework::Loop::VLoop;

use strict;
use warnings;

use Scalar::Util qw(weaken reftype);
use curry::weak;

=head1 NAME

    VV::Framework::Loop::VLoop

=head1 SYNOPSIS

use VV::Framework::Loop::VLoop;

# Will use $VLOOP_MODE = 'calling'
my $vloop = VV::Framework::Loop::VLoop->new(0);
# Will use $VLOOP_MODE = 'passing'
my $vloop = VV::Framework::Loop::VLoop->new(1);
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
