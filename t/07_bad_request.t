use strict;
use Test::More;

#plan skip_all => 'MSWin32 does not have a proper fork()' if $^O eq 'MSWin32';

plan 'no_plan';

use HTTP::Request;
use POE qw(Wheel::Run Filter::Reference Filter::Line);
use POE::Kernel;
use POE::Component::Server::SimpleHTTP;
use LWP;

my $PORT = 2080;
my $IP = "localhost";

####################################################################
POE::Component::Server::SimpleHTTP->new(
    	'ALIAS'    => 'SimpleHTTP',
    	'ADDRESS'  => "$IP",
    	'PORT'     => $PORT,
    	'HANDLERS' => [
        	{
            	'DIR'     => qr/^\/hello\.html$/,
            	'SESSION' => 'HTTPD',
            	'EVENT'   => 'hello',
        	},
    	],
	SETUPHANDLER => { SESSION => 'HTTPD', EVENT => '_tests', },
	) or die 'Unable to create the HTTP Server';
	
POE::Session->create(
    	inline_states => {
        	'_start'    => sub { $_[KERNEL]->alias_set('HTTPD');
				     #$poe_kernel->delay( '_tests', 8 );
				     return;
			       },
        	'hello'     => \&handle_hello,
        	'not_found' => \&handle_not_found,
		'_tests'    => \&_start_tests,
		'_close'    => \&_close,
                '_stdout'   => \&_stdout,
                '_stderr'   => \&_stderr,
                '_sig_chld' => \&_sig_chld,
    	},
);
	
$poe_kernel->run;
exit 0;

sub handle_hello 
{
   	my ( $request, $response, $dirmatch ) = @_[ ARG0 .. ARG2 ];
	
   	$response->code(200);
  	$response->content("Hello");
	
  	$_[KERNEL]->post('SimpleHTTP', 'DONE', $response );
	return;
}

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
  $poe_kernel->post( 'SimpleHTTP', 'SHUTDOWN' );
  $poe_kernel->alias_remove( 'HTTPD' );
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

######################################################################
sub _tests
{                      
    sleep 4;
    binmode(STDOUT) if $^O eq 'MSWin32';
    my $filter = POE::Filter::Reference->new();

    my $results = [ ];

    my $ua = LWP::UserAgent->new();
    my $request = HTTP::Request->new( GEt => "http://$IP:$PORT/hello.html");
    my $resp = $ua->request( $request );
    push @$results, { test => 'Good, got back response with correct error code from bad request.',
		      result => ( $resp->code eq '200' ) };
    #diag( $resp->content );
    my $replies = $filter->put( $results );
    print STDOUT @$replies;
    return;
}
