package Spread::Client::Frame;
use strict;
use warnings;
use Spread::Client::Constant qw(REG_MEMB_MESS
                                REGULAR_MESS
                                TRANSITION_MESS
                                MEMBERSHIP_MESS
                                SPREAD_VERSION
                                CAUSED_BY_LEAVE);

# All lengths are calculated in bytes
use bytes;
use Exporter 'import';

# our EXPORT_OK;
# TODO considering moving this over to EXPORT_OK
# since it might make sense to push this out aa a seperate thing
our @EXPORT= qw(build_connect_message
                build_auth_message
                build_standard_message
                parse_message_header
                parse_message_groups
                parse_message_body
                JOIN_MESS 
                LEAVE_MESS 
                KILL_MESS
                DEFAULT_SEND_MESS
               );

# HEADER INFORMATION INDEXES
sub SERVICE_TYPE () { 0 }
sub SENDER       () { 1 }
sub NUM_MEMBERS  () { 2 }
sub HINT         () { 3 }
sub DATA_LEN     () { 4 }

# version constants
sub MAJOR_VERSION () { 4 }
sub MINOR_VERSION () { 0 }
sub PATCH_VERSION () { 0 }
sub PRIORITY      () { 0 }

# version bitmasks
sub SPREAD3 () { 0x03000000 }
sub SPREAD4 () { 0x04000000 }

# Internal messaging constants
sub JOIN_MESS ()         { 0x00010000 }
sub LEAVE_MESS ()        { 0x00020000 }
sub KILL_MESS ()         { 0x00020000 }
sub DEFAULT_SEND_MESS () { 0x00000002 } # This is the same as reliable mess

# Template for packing header of each message
my $pack_template = 'C4a32C12';

# Message building functions
sub build_connect_message {
    my %args = @_;

    
    # pack string N5Ca
    # TODO use config for versioning here
    return pack( 'C5a*',
                 4,
                 0,
                 0,
                 1,
                 length( $args{private_name} ),
                 $args{private_name},
               );
}

sub build_auth_message {
    my %args = @_;

    # This should basically end up being NULL ord'ed
    my @auth_method = map { ord $_ } (split //, (split /\s/, $args{auth_method})[0]);

    while (scalar @auth_method < 90) {
        push @auth_method, 0;
    }

    # pack string
    return pack( 'C90',
                 @auth_method,
               );
}

sub build_standard_message {
    my %args = @_;

    my @message; 

    # Add Service type to front of message
    _add_to_message(\@message, $args{type} );

    # Add private group name
    push @message, ($args{from_group});

    # Get the length of to group names
    my $group_len = scalar @{$args{to_groups}};
    my $data_len = $args{data} ? length( $args{data} )
                               : 0;

    # Add to groups, group length
    _add_to_message( \@message,  $group_len);
    # Add message hint
    _add_to_message( \@message, 0 );
    # Add data length
    _add_to_message( \@message, $data_len);

    # Add to group names
    push @message, ( @{ $args{to_groups} } );

    # Add the correct number of addition template formats for pack
    my $full_template = $pack_template . ('a32' x $group_len);

    $full_template .= $data_len ? 'a*'
                                : 'a0';

    if( $data_len ) {
        push @message, ( $args{data} );
    }

    return pack( $full_template, @message);
}

# Converts to integer values to a byte array
sub _add_to_message {
    # $_[0] is a reference, there is no need return it
    for my $bitshift (24, 16, 8, 0) {
        push @{$_[0]}, (($_[1] >> $bitshift) & 0xFF);
    }
}

# Parse functions
sub parse_message_header {

    # $_[0] = buffer
    return unpack('IZ32iii', ${$_[0]});
}

sub parse_message_groups {

    # $_[0] = buffer
    # $_[1] = member count

    return [ unpack('(Z32)' . $_[1], ${$_[0]}) ];
}

sub parse_message_body {

    # $_[0] = buffer
    # $_[1] = service_type

    # We do different things based on what type of message
    if( $_[1] & REG_MEMB_MESS ) {

        my ($proc_id, $time, $index, $vs_group_number) = unpack( 'iiii', ${$_[0]});
        # Spread 4 apparently has somethign in an extra 2 integers
        my (@members);

        if((SPREAD_VERSION + 0) & SPREAD4 ) {
            (@members) = unpack( "x[iiiiii](Z32)$vs_group_number", ${$_[0]});
        }
        else { # Spread 3
            (@members) = unpack( "x[iiii](Z32)$vs_group_number", ${$_[0]});
        }

        # return membership listing as message
        return { proc_id => $proc_id, time => $time, index => $index, members => \@members};
    }
    elsif( $_[1] & REGULAR_MESS) {

        return ${$_[0]};
    }
    elsif( $_[1] & TRANSITION_MESS) {
        my ($proc_id, $time, $index) = unpack( 'iii', ${$_[0]});

        return { proc_id => $proc_id, time => $time, index => $index};
    }
    elsif( $_[1] & MEMBERSHIP_MESS and $_[1] & CAUSED_BY_LEAVE) { # self leave message
        # TODO(NOTE) docs say i should get something in the vs_group_stuff but i'm getting squat
        my ($proc_id, $time, $index, $vs_group_number, $member) = unpack( 'iiiiZ32', ${$_[0]});

        # return membership listing as message
        return { proc_id => $proc_id, time => $time, index => $index, members => [ $member ] };
    }

    # If nothing matches or shouldn't match just return nothing
    return;
}

1;
