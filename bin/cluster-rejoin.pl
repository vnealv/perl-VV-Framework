#!/usr/bin/env perl 
use strict;
use warnings;

use IO::Async::Loop;
use Future::AsyncAwait;
use Syntax::Keyword::Try;
use Net::Async::Redis;
use Net::Async::Redis::Cluster;

use Socket qw(unpack_sockaddr_in inet_ntoa);
use Log::Any qw($log);
use Log::Any::Adapter qw(Stdout), log_level => 'debug';
use IO::Async::Resolver;

my $loop = IO::Async::Loop->new;

my $idx = 0;
my @ip;
while(1) {
    try {
        my (@addr) = await $loop->resolver->getaddrinfo(
            host    => "redis-node-$idx",
            service => "6379",
            protocol => 6,
        ) or last;
        for my $addr (@addr) {
            my $ip = inet_ntoa(''. unpack_sockaddr_in($addr->{addr}));
            $log->infof('Have Redis node at %s - %s', $ip, $addr);
            push @ip, $ip;
        }
        ++$idx;
    } catch($e) {
        last if $e =~ /Name or service not known/i;
        die 'Unexpected error in lookup - ' . $e;
    }
}

$log->infof('Have a total of %d Redis nodes', 0 + @ip);

for my $node (@ip) {
    try {
        $loop->add(
            my $redis = Net::Async::Redis->new(
                host => $node,
            )
        );
        await $redis->connect;
        # We'll expect this to return ERR if we provide an invalid node,
        # although it may not immediately fail if the node exists and
        # was not originally part of the cluster
        for my $target (@ip) {
            await $redis->cluster_meet($target => 6379);
        }
    } catch($e) {
        $log->errorf('Failed to join %s to the cluster: %s', $node, $e);
    }
}

$log->infof('All nodes have now joined.');


try {
    $loop->add(
        my $cluster = Net::Async::Redis::Cluster->new( client_side_cache_size =>  0 ) 
    );

	$log->info('Testing Cluster, connecting to main node ...');
        await $cluster->bootstrap(
            host => 'redis-node-0',
	        port => 6379
        );
	my $set = await $cluster->set('some_key', "From node:redis-node-0");
	$log->infof('Set response: %s', $set);
	my $get = await $cluster->get('some_key');
	$log->infof('Get Key: %s', $get);
} catch ($e) {
    $log->errorf('Failed to set/get key from cluster. Node: redis-node-0 | Error: %s', $e);
}

$log->infof('Cluster has been tested.');
