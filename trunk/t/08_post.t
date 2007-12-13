use strict;
use Test::More;

#plan skip_all => 'MSWin32 does not have a proper fork()' if $^O eq 'MSWin32';

plan tests => 2;

use LWP::UserAgent;
use LWP::ConnCache;
use HTTP::Request;
use POE qw(Wheel::Run Filter::Reference Filter::Line);
use POE::Kernel;
use POE::Component::Server::SimpleHTTP;
use Data::Dumper;

my $PORT = 2080;
my $IP = "localhost";

####################################################################
POE::Component::Server::SimpleHTTP->new(
                'ALIAS'         =>      'HTTPD',
                'ADDRESS'       =>      "$IP",
                'PORT'          =>      $PORT,
                'HOSTNAME'      =>      'pocosimpletest.com',
                'HANDLERS'      =>      [
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
			'_sig_chld'	=> \&_sig_chld,
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
    
    $response->content(join ' ', reverse split (/~/, $request->content) );
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
    
   my $req = HTTP::Request->new(POST => "http://$IP:$PORT/");
   
   $req->content("brother !~we need to get off this island");
   
   my $resp = $UA->request($req);

   die "resp=", $resp->as_string unless $resp->is_success;
   push @$results, { test => "got index", result => $resp->is_success };
   my $content=$resp->content;
   push @$results, { test => qq{received "$content"}, result => $content =~ /^we/ };
   my $replies = $filter->put( $results );
   print STDOUT @$replies;
   return;
}


