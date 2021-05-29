package VV::Framework::Service;

use strict;
use warnings;

# VERSION

use utf8;

=encoding utf8

=head1 NAME

VV::Framework::Service - VV microservice Service abstraction

=head1 SYNOPSIS

 my $service = VV::Framework::Service->new;

=head1 DESCRIPTION

=head1 Implementation

Note that this is defined as a role, so it does not provide
a concrete implementation - instead, it defines VV microservices implementation
by requiring needed methods and setting default ones.

=cut

no indirect qw(fatal);

use Object::Pad;

role VV::Framework::Service;

use Log::Any qw($log);
use Syntax::Keyword::Try;
use Future::AsyncAwait;

=head1 METHODS

The following methods are required in any concrete classes which implement this role.

=head2 start

Activate microservice - By invoking implementation starting logic
Expected to return a L<Future> which resolves once we think this instance is ready
and able to process requests.

=cut

# It seems that there is an issue with async methods and Object::Pad Roles.
# requires start;


async method health ($message) {
	return {success => 'ok'};
}

async method request ($message) {
	return {success => 'ok'};

}

1;
