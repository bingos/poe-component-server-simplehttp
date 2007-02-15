#!/usr/bin/perl -w

use strict;
use Test::More tests => 12;

use LWP::UserAgent;
use LWP::ConnCache;
use HTTP::Request;
use POE;
use POE::Kernel;
use POE::Component::Server::SimpleHTTP;

my $PORT = 2080;
my $IP = "localhost";

my $pid = fork;
die "Unable to fork: $!" unless defined $pid;

END {
    if ($pid) {
        kill 2, $pid or warn "Unable to kill $pid: $!";
    }
}

####################################################################
if ($pid)  # we are parent
{                      
    # stop kernel from griping
    ${$poe_kernel->[POE::Kernel::KR_RUN]} |=
      POE::Kernel::KR_RUN_CALLED;

    diag("$$: Sleep 2...");
    sleep 2;
    diag("continue");

    my $UA = LWP::UserAgent->new;
  again:
    my $req=HTTP::Request->new(GET => "http://$IP:$PORT/");
    my $resp=$UA->request($req);

    ok($resp->is_success, "got index") or die "resp=", Dump $resp;
    my $content=$resp->content;
    ok($content =~ /this is top/, "got top index");

    $req=HTTP::Request->new(GET => "http://$IP:$PORT/honk/");
    $resp=$UA->request($req);

    ok($resp->is_success, "got something");
    $content=$resp->content;
    ok($content =~ /this is honk/, "something honked");

    $req=HTTP::Request->new(GET => "http://$IP:$PORT/bonk/zip.html");
    $resp=$UA->request($req);
    ok(($resp->is_success and $resp->content_type eq 'text/html'),
       "get text/html");
    $content=$resp->content;
    ok($content =~ /my friend/, 'my friend');

    unless ($UA->conn_cache) {
        diag( "Enabling Keep-Alive and going again" );
        $UA->conn_cache( LWP::ConnCache->new() );
        goto again;
    }
}

####################################################################
else  # we are the child
{                          
    POE::Component::Server::SimpleHTTP->new(
                'ALIAS'         =>      'HTTPD',
                'ADDRESS'       =>      "$IP",
                'PORT'          =>      $PORT,
                'HOSTNAME'      =>      'pocosimpletest.com',
                'HANDLERS'      =>      [
                        {
                                'DIR'           =>      '/honk/',
                                'SESSION'       =>      'HTTP_GET',
                                'EVENT'         =>      'HONK',
                        },
                        {
                                'DIR'           =>      '/bonk/zip.html',
                                'SESSION'       =>      'HTTP_GET',
                                'EVENT'         =>      'BONK2',
                        },
                        {
                                'DIR'           =>      '/bonk/',
                                'SESSION'       =>      'HTTP_GET',
                                'EVENT'         =>      'BONK',
                        },
                        {
                                'DIR'           =>      '/',
                                'SESSION'       =>      'HTTP_GET',
                                'EVENT'         =>      'TOP',
                        },
                ],
    );
    # Create our own session to receive events from SimpleHTTP
    POE::Session->create(
                inline_states => {
                        '_start'        => sub {   $_[KERNEL]->alias_set( 'HTTP_GET' ) },
                        'TOP'           => \&top,
                        'HONK'          => \&honk,
                        'BONK'          => \&bonk,
                       	'BONK2'         => \&bonk2,
                },
    );
    $poe_kernel->run;
}


#######################################
sub top
{
    my ($request, $response) = @_[ARG0, ARG1];
    $response->code(200);
    $response->content_type('text/plain');
    $response->content("this is top");
    $_[KERNEL]->post( 'HTTPD', 'DONE', $response );
}

#######################################
sub honk
{
    my ($request, $response) = @_[ARG0, ARG1];
    $response->code(200);
    $response->content_type('text/plain');
    $response->content("this is honk");
    $_[KERNEL]->post( 'HTTPD', 'DONE', $response );
}

#######################################
sub bonk
{
    my ($request, $response) = @_[ARG0, ARG1];
    $response->code(200);
    $response->content_type('text/plain');
    $response->content("this is bonk");
    $_[KERNEL]->post( 'HTTPD', 'DONE', $response );
}

#######################################
sub bonk2
{
    my ($request, $response) = @_[ARG0, ARG1];
    $response->code(200);
    $response->content_type('text/html');
    $response->content(<<'    HTML');
<html>
<head><title>YEAH!</title></head>
<body><p>This, my friend, is the page you've been looking for.</p></body>
</html>
    HTML
    $_[KERNEL]->post( 'HTTPD', 'DONE', $response );
}

