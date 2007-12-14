use strict;
use Test::More;

#plan skip_all => 'MSWin32 does not have a proper fork()' if $^O eq 'MSWin32';

plan tests => 22;

use LWP::UserAgent;
use LWP::ConnCache;
use HTTP::Request;
use POE qw(Wheel::Run Filter::Reference Filter::Line);
use POE::Kernel;
use POE::Component::Server::SimpleHTTP;

my $PORT = 2080;
my $IP = "localhost";

POE::Component::Server::SimpleHTTP->new(
                'ALIAS'         =>      'HTTPD',
                'ADDRESS'       =>      "$IP",
                'PORT'          =>      $PORT,
                'HOSTNAME'      =>      'pocosimpletest.com',
                'HANDLERS'      =>      [
                        {
                                'DIR'           =>      '^/honk/',
                                'SESSION'       =>      'HTTP_GET',
                                'EVENT'         =>      'HONK',
                        },
                        {
                                'DIR'           =>      '^/bonk/zip.html',
                                'SESSION'       =>      'HTTP_GET',
                                'EVENT'         =>      'BONK2',
                        },
                        {
                                'DIR'           =>      '^/bonk/',
                                'SESSION'       =>      'HTTP_GET',
                                'EVENT'         =>      'BONK',
                        },
                        {
                                'DIR'           =>      '^/$',
                                'SESSION'       =>      'HTTP_GET',
                                'EVENT'         =>      'TOP',
                        },
                ],
		SETUPHANDLER => { SESSION => 'HTTP_GET', EVENT => '_tests', },
    );
    # Create our own session to receive events from SimpleHTTP
POE::Session->create(
                inline_states => {
                        '_start'        => sub {   $poe_kernel->alias_set( 'HTTP_GET' );
						   #$poe_kernel->delay( '_tests', 8 );
						   return;
					   },
                        '_tests'        => \&_start_tests,
                        'TOP'           => \&top,
                        'HONK'          => \&honk,
                        'BONK'          => \&bonk,
                       	'BONK2'         => \&bonk2,
                        '_close'        => \&_close,
                        '_stdout'       => \&_stdout,
                        '_stderr'       => \&_stderr,
                        '_sig_chld'     => \&_sig_chld,
                        'on_close'      => \&on_close,
                },
);
$poe_kernel->run;
exit 0;

sub _start_tests {
  my ($kernel,$heap) = @_[KERNEL,HEAP];
  $heap->{_wheel} = POE::Wheel::Run->new(
	Program => \&_tests,
	StdioFilter  => POE::Filter::Reference->new(),
	StderrFilter => POE::Filter::Line->new(),
	CloseEvent => '_close',
	ErrorEvent => '_close',
	StdoutEvent => '_stdout',
	StderrEvent => '_stderr',
  );
  $kernel->sig_child( $heap->{_wheel}->PID(), '_sig_chld' ) unless $^O eq 'MSWin32';
  return;
}

sub _close {
  delete $_[HEAP]->{_wheel};
  $poe_kernel->post( 'HTTPD', 'SHUTDOWN' );
  $poe_kernel->alias_remove( 'HTTP_GET' );
  return;
}

sub _stdout {
  ok( $_[ARG0]->{result}, $_[ARG0]->{test} );
  return;
}

sub _stderr {
  print STDERR $_[ARG0], "\n";
  return;
}

sub _sig_chld {
  return $poe_kernel->sig_handled();
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
    my $c = $response->connection;
    $c->on_close( 'on_close', [ $c->ID, "something" ], "more" );
    $response->code(200);
    $response->content_type('text/plain');
    $response->content("this is honk");
    $_[KERNEL]->post( 'HTTPD', 'DONE', $response );
}

#######################################
sub on_close
{
    my( $args, $more ) = @_[ARG0, ARG1];
    ok( ($args and $more), "on_close with 2 arguments" );
    ok( $args->[0], "First is the wheel ID=$args->[0]" );
    is( $args->[1], 'something', " ... with some extra data" );
    is( $more, 'more', "Second is a string" );
}

#######################################
sub bonk
{
    my ($request, $response) = @_[ARG0, ARG1];
    fail( "bonk should never be called" );
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

####################################################################
sub _tests
{                      
    sleep 4;
    binmode(STDOUT) if $^O eq 'MSWin32';
    my $filter = POE::Filter::Reference->new();

    my $results = [ ];
    my $UA = LWP::UserAgent->new;
    again:
    my $req=HTTP::Request->new(GET => "http://$IP:$PORT/");
    my $resp=$UA->request($req);

    die "resp=", $resp->as_string() unless $resp->is_success;
    push @$results, { test => "got index", result => $resp->is_success };
    my $content=$resp->content;
    push @$results, { test => "got top index", result => $content =~ /this is top/ };

    $req=HTTP::Request->new(GET => "http://$IP:$PORT/honk/");
    $resp=$UA->request($req);

    push @$results, { test => "got something", result => $resp->is_success };
    $content=$resp->content;
    push @$results, { test => "something honked", result => $content =~ /this is honk/ };

    $req=HTTP::Request->new(GET => "http://$IP:$PORT/bonk/zip.html");
    $resp=$UA->request($req);
    push @$results, { test => "get text/html", result => 
			($resp->is_success and $resp->content_type eq 'text/html') };
    $content=$resp->content;
    push @$results, { test => "my friend", result => $content =~ /my friend/ };
    
    # Test for 404
    #diag('Test for 404');
    $req=HTTP::Request->new(GET => "http://$IP:$PORT/wedonthaveone");
    $resp=$UA->request($req);
    
    #is($resp->code, 404, "404 code returned from bad handler call, this is good.");
    push @$results, { test => "404 code returned from bad handler call, this is good.", 
			result => ( $resp->code eq '404' ) };

    unless ($UA->conn_cache) {
        #diag( "Enabling Keep-Alive and going again" );
        $UA->conn_cache( LWP::ConnCache->new() );
        goto again;
    }
    my $replies = $filter->put( $results );
    print STDOUT @$replies;
    return;
}


