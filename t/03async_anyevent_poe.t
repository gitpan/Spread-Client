use strict;
use warnings;

use Test::More tests => 8;
use POE;
use AnyEvent;

BEGIN { use_ok('Spread::Client') }
use Spread::Client::Constant ':all';

SKIP: {
    my $have_poe = eval { require POE; require AnyEvent; 1; };

    skip 'SPREAD_NAME environment variable not defined or we are missing AnyEvent/POE', 7
        unless $ENV{SPREAD_NAME} and $have_poe;
    my $spread_name = $ENV{SPREAD_NAME} || '4803@localhost';
    
    my $private_name = 'mrperla' . int(rand(99));
    my $group_name = 'league-100' || 'test_group' . int(rand(99));
    my $orig_message = 'this is an async message';
    
    # Connect
    my $conn;
    eval {
        # Connect
        $conn = Spread::Client::connect(
            spread_name   => $spread_name,
            private_name  => $private_name,
            connect_class => 'Async::AnyEvent',
        );
    };
    ok(!$@, 'connect succesful');
    diag('Exception: ' . $@)
        if $@;
    
    # set message count before exit
    my $message_max = 2;
    my $message_count = 0;
    
    $conn->message_callback( \&handle_message );
    
    Spread::Client::join( conn   => $conn,
                        groups => [ $group_name ],
                        );
    
    Spread::Client::multicast( conn    => $conn,
                            type    => SAFE_MESS,
                            groups  => [ $group_name ],
                            message => $orig_message,
                            );
        
    sub handle_message { 
        my ($conn, @message) = @_;
    
        my ($service_type, $sender, $groups, $mess_type, $endian, $message) =
            @message;
    
        $message_count++;
    
        if( $message_count == 1 ) {
            is($sender, $group_name, 'Group name matches this is good.');
            ok( ref $message eq 'HASH', 'We got back a join message, this is good.');
            is($groups->[0], $conn->private_group, 'Groups came back correctly, this is good.');
            is($message->{members}->[0], $conn->private_group, 'Shows we joined correctly, this is good.');
        }
        else {
            is($sender, $conn->private_group, 'Sender matches this is good.');
            is($message, $orig_message, 'Message matches this is good.');
        } 
    
        if( $message_count >= $message_max ) {
    
            Spread::Client::leave( conn   => $conn,
                                groups => [ $group_name ],
                                );
        
            Spread::Client::disconnect( conn => $conn );
            POE::Kernel->stop();
        }
    }
    
    POE::Kernel->run();

}
