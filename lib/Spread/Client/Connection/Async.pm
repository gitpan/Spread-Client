package Spread::Client::Connection::Async;
use strict;
use warnings;
use bytes;

# TODO do this smarter
$SIG{PIPE} = 'IGNORE';

use base qw/Spread::Client::Connection/;
use Spread::Client::Frame;
use Spread::Client::Constant ':all';

# States
use constant READING_MESS_HEADER => 0;
use constant READING_GROUPS => 1;
use constant READING_MESSAGE => 2;

# Read sizes indexes
use constant MESS_HEADER_SIZE => 0;
use constant MESS_GROUPS_SIZE => 1;
use constant MESSAGE_SIZE => 2;

# Current Message indexes
use constant SERVICE_TYPE => 0;
use constant SENDER => 1;
use constant GROUPS => 2;
use constant MESS_TYPE => 3;
use constant ENDIAN => 4;
use constant MESSAGE => 5;

#
our %init = ( messages           => [],
              read_sizes         => [48, 0, 0],
              private_group      => undef,
              buffer             => undef,
              messages           => undef,
              current_message    => undef,
              state              => undef,
              message_callback   => undef,
              session_connected  => undef,
            );

sub init {
    my $self = shift;

    $self->{$_} = $init{$_} for keys %init;

    $self->reset_state;
}

sub is_async { return 1 }
sub close { die "ABSTRACT\n" } # close socket
sub read { die "ABSTRACT\n" } # read data off socket; Implement in your derived class
sub write { die "ABSTRACT\n" } # write data to socket; Implement in your derived class
sub sock { die "ABSTRACT\n" } # returns raw socket object; Implement in your derived class
sub watch_read { die "ABSTRACT\n" } # toggle for watching reads on this connection; Implement in your derived class

sub reset_state {
    my $self = shift;

    # TODO presize this since we already know how large it will be
    $self->{current_message} = [];
    $self->{buffer} = '';
    $self->{state} = READING_MESS_HEADER;
    $self->{read_sizes}->[$_] = 0 for (MESS_GROUPS_SIZE, MESSAGE_SIZE);
}

sub message_callback {
    my $self = shift;

    $self->{message_callback} = $_[0]
            if $_[0];

    return $self->{message_callback};
}

sub set_header {
    my $self = shift;

    my ($service_type, $sender, $num_members, $hint, $data_len) = parse_message_header( \$self->{buffer} );

    # Set read sizes from header
    $self->{read_sizes}->[MESS_GROUPS_SIZE] = $num_members * 32;
    $self->{read_sizes}->[MESSAGE_SIZE] = $data_len;

    # Fill in what we have into current message
    $self->{current_message}->[SERVICE_TYPE] = $service_type;
    $self->{current_message}->[SENDER] = $sender;
    $self->{current_message}->[ENDIAN] = undef;
    $self->{current_message}->[MESS_TYPE] = undef;

    $self->{buffer} = substr( $self->{buffer},
                              $self->{read_sizes}->[MESS_HEADER_SIZE],
                            );
}

sub set_groups {
    my $self = shift;

    my $num_of_groups = $self->{read_sizes}->[MESS_GROUPS_SIZE] / 32;

    $self->{current_message}->[GROUPS] = parse_message_groups( \$self->{buffer}, $num_of_groups);

    $self->{buffer} = substr( $self->{buffer},
                              $self->{read_sizes}->[MESS_GROUPS_SIZE],
                            );
}

sub set_message {
    my $self = shift;

    $self->{current_message}->[MESSAGE] = parse_message_body( \$self->{buffer},
                                                              $self->{current_message}->[SERVICE_TYPE],
                                                            );
    $self->{buffer} = substr( $self->{buffer},
                              $self->{read_sizes}->[MESSAGE_SIZE],
                            );
}

sub dispatch_message_and_reset_state {
    my $self = shift;
    my @message;

    $message[$_] = $self->{current_message}->[$_] for (0..5);
    
    $self->reset_state();

    if( $self->{message_callback} ) { 
        $self->{message_callback}->( $self, @message);
    }
    else {
        push @{$self->{messages}}, \@message;
    } 
}

sub private_group {
    my $self = shift;

    $self->{private_group} = $_[0]
            if $_[0];

    return $self->{private_group};
}

sub receive {
    my $self = shift;

    if( $self->{state} == READING_MESS_HEADER ) {

        my $left_to_read = $self->{read_sizes}->[MESS_HEADER_SIZE] - length $self->{buffer};

        if( $left_to_read > 0 ) {
            unless( $self->{buffer} .= ${$self->read( $left_to_read, 1 )} ) {
                $self->close();
            }
        }

        if( length $self->{buffer} >= $self->{read_sizes}->[MESS_HEADER_SIZE]) {
            $self->set_header();
            $self->{state} = READING_GROUPS;
        }
    }

    if( $self->{state} == READING_GROUPS ) {

        my $left_to_read = $self->{read_sizes}->[MESS_GROUPS_SIZE] - length $self->{buffer};

        if( $left_to_read > 0 ) {
            unless( $self->{buffer} .= ${$self->read( $left_to_read, 1 )} ) {
                $self->close();
            }
        }

        if( length $self->{buffer} >= $self->{read_sizes}->[MESS_GROUPS_SIZE]) {
            $self->set_groups();
            $self->{state} = READING_MESSAGE;
        }
    }

    if( $self->{state} == READING_MESSAGE ) {

        my $left_to_read = $self->{read_sizes}->[MESSAGE_SIZE] - length $self->{buffer};

        if( $left_to_read > 0 ) {
            unless( $self->{buffer} .= ${$self->read( $left_to_read, 1 )} ) {
                $self->close();
            }
        }

        if( length $self->{buffer} >= $self->{read_sizes}->[MESSAGE_SIZE] ) {
            $self->set_message();
            $self->dispatch_message_and_reset_state();
        }
    }
}

sub get_queued_messages {
    my $self = shift;

    my $messages = $self->{messages};
    $self->{messages} = [];

    return wantarray ? @$messages
                     : $messages;
}

1;
