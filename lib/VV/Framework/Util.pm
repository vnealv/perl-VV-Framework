package VV::Framework::Util;

use strict;
use warnings;

use Exporter 'import';
use Sys::Hostname qw(hostname);

our @EXPORT_OK = qw(whoami subscription_name);

# This will in fact act as a had constrain on VV Framework 
# where only one service can run per container/system
sub whoami {    
    return hostname();
}

sub subscription_name {
    my ($domain, $service_name) = @_;
    return join '_', join('::', (split('::', $domain))[0], $service_name), 'SUBSCR';
}
