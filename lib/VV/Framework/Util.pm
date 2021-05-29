package VV::Framework::Util;

use strict;
use warnings;

use Exporter 'import';
use Sys::Hostname qw(hostname);

our @EXPORT_OK = qw(whoami service_name);

# This will in fact act as a had constrain on VV Framework 
# where only one service can run per container/system
sub whoami {    
    return hostname();
}

sub service_name {

}
