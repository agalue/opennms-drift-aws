#!/usr/bin/perl

use strict;

open OUT, ">hosts";

print OUT <<EOF;
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6

192.168.205.142\tminion\tminion.local
EOF

my @data = `pushd ../../ >/dev/null && terraform output`;
foreach $_ (@data) {
  chop;
  s/ //g;
  my ($app, $list) = split /=/;
  my @addresses = split /,/, $list;
  my $index = 1;
  foreach my $ip (@addresses) {
    my $srv = "$app$index";
    printf OUT "%s\t%s\t%s\n", $ip, $srv, "$srv.local";
    $index++;
  }
}

close OUT;

print "Hosts file updated!\n";

