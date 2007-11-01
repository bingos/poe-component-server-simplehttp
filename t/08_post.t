use strict;
use Test::More;

plan skip_all => 'MSWin32 does not have a proper fork()' if $^O eq 'MSWin32';

plan tests => 2;

use LWP::UserAgent;
use LWP::ConnCache;
use HTTP::Request;
use POE;
use POE::Kernel;
use POE::Component::Server::SimpleHTTP;
use Data::Dumper;

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
    
   my $req = HTTP::Request->new(POST => "http://$IP:$PORT/");
   
   $req->content("brother !~we need to get off this island");
   
   my $resp = $UA->request($req);

   ok($resp->is_success, "got index") or die "resp=", $resp;
   my $content=$resp->content;
   ok($content =~ /^we/, 'received "'.$content.'"');

   exit;
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
                                'DIR'           =>      '^/$',
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
    
    $response->content(join ' ', reverse split (/~/, $request->content) );
    $_[KERNEL]->post( 'HTTPD', 'DONE', $response );
}
