# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Original Code is the PAMBAAN Bugzilla Extension.
#
# The Initial Developer of the Original Code is YOUR NAME
# Portions created by the Initial Developer are Copyright (C) 2015 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Marco Pauls <info@mgp-it.de>

package Bugzilla::Extension::PAMBAAN::Lane;
use strict;

our $version="0.2";

use base qw(Bugzilla::Object Exporter);
our @EXPORT = qw();


use Data::Dumper;
use Scalar::Util qw( blessed );

use Bugzilla;
use Bugzilla::Search;
use Bugzilla::Search::Saved;
use Bugzilla::CGI;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Util qw( detaint_natural detaint_signed trim );

use Bugzilla::Extension::PAMBAAN::Board;
use Bugzilla::Extension::PAMBAAN::Search;

use constant DB_TABLE => 'pambaan_board_lanes';

use constant VALID_COLUMNS => qw( id name sortkey description namedquery_name namedquery_sharer_id board_id wip_warning_threshold wip_overload_threshold space_occupied color);


sub DB_COLUMNS {
    my $t = DB_TABLE;
    my @columns = map{ "$t.$_" } VALID_COLUMNS;
    return @columns;
 
};


use constant NUMERIC_COLUMNS => qw(
    id
    namedquery_sharer_id
    board_id
    wip_warning_threshold
    wip_overload_threshold
    space_occupied
);

use constant UPDATE_COLUMNS => qw(
    name
    sortkey
    description
    namedquery_name
    namedquery_sharer_id
    color
    wip_warning_threshold
    wip_overload_threshold
    space_occupied
);

use constant NAME_FIELD => 'name';
use constant ID_FIELD   => 'id';
use constant LIST_ORDER => 'board_id, sortkey';
use constant VALIDATORS =>  {
                                name                    => \&_check_name,
                                wip_warning_threshold   => \&_check_threshold,
                                wip_overload_threshold  => \&_check_threshold,
                                color                   => \&_check_color,
                                space_occupied          => \&_check_space_occupied,
                            };

use constant PAMBAAN_MAX_LANE_SIZE => 127;                            

use constant BUGLIST_SELECTCOLUMNS => [ "bug_id", "bug_severity", "short_desc", "priority", "bug_status", "product", "component", "assigned_to_realname", "assigned_to" ];
use constant BUGLIST_ORDERSTRINGS  => [ "bug_severity", "bug_id" ];

#
#                                                                         ______________________________ 
#                                                                        /                              \
# ---------------------------------------------------------------------- | The Bugzilla Lifecycle Stuff  |
#                                                                        \______________________________/
#

sub new {
    my $invocant = shift;
    my $params = shift;
    my $class = ref($invocant) || $invocant;

    if (ref($params) eq 'HASH' ) {
        my $name = $params->{name};
        
        my $board_id;
        my $board = delete $params->{board};
        SWITCH: {
            $board && do { $board_id = $board->{id}; last SWITCH; };
            { $board_id = $params->{board_id}; last SWITCH; };
        }
        $params->{board_id} = $board_id;
        
        
        ThrowCodeError('bad_arg', {argument => 'name', function => "${class}::new"}) if !defined( $name );
        ThrowCodeError('bad_arg', {argument => 'board_id', function => "${class}::new"}) if !defined( $board_id );

        detaint_natural($board_id) || ThrowCodeError('param_must_be_numeric', {function => $class . '::new', param => 'board_id'});

        my $condition = 'board_id = ? AND name = ?';
        my @values = ($board_id, $name);
        $params = { condition => $condition, values => \@values };
    }

    unshift @_, $params;
    
    my $self = $class->SUPER::new(@_);
    if ($self) {
        ### $self->{user} = $user if blessed $user;

        # Some DBs (read: Oracle) incorrectly mark the query string as UTF-8
        # when it's coming out of the database, even though it has no UTF-8
        # characters in it, which prevents Bugzilla::CGI from later reading
        # it correctly.
        utf8::downgrade($self->{query}) if utf8::is_utf8($self->{query});
    }
    return $self;
}

sub create {
    my $invocant = shift;
    my $class = ref($invocant) || $invocant;
    my $params = shift;
    
    if (ref($params) eq 'HASH' ) {
        my $board_id;
        my $board = delete $params->{board};
        SWITCH: {
            $board && do { $board_id = $board->{id}; last SWITCH; };
            { $board_id = $params->{board_id}; last SWITCH; };
        }
        $params->{board_id} = $board_id;
    }
    
    unshift @_, $params;
    my $self = $class->SUPER::create( @_ );
    
    return $self;
}



sub transientnew {
    my $invocant = shift;
    my $class = ref($invocant) || $invocant;
    my ($param) = @_;
    
    my $lane = {};   
    bless( $lane, $class );
    
    if (ref $param eq 'HASH') {
        my %validcolumns =  map { $_ => 1 } VALID_COLUMNS;
        
        while ( my($key,$value) = each %{$param} ) {
            $lane->{$key} = $value if ( exists $validcolumns{$key} );
        } 
    } else {
        $lane->{name} = $param;
    }
    
    return $lane;
}

sub get_all_for_board {
    my $invocant = shift;
    my $class = ref($invocant) || $invocant;
    my $param = shift;
    
    my $board_id;
    my $what= ref( $param );
    SWITCH: {
        $what eq 'HASH' && do { $board_id = $param->{board_id}; last SWITCH; };
        $what eq 'Bugzilla::Extension::PAMBAAN::Board' && do { $board_id = $param->{id}; last SWITCH; };
    }

    ThrowCodeError('bad_arg', {argument => 'board_id', function => "${class}::new"}) if !defined( $board_id );
    detaint_natural($board_id) || ThrowCodeError('param_must_be_numeric', {function => "$class::get_all_for_board", param => 'board_id'});
    
    #
    # Could also have used Bugzilla::Object->matc( { board_id => $board_id } )
    return $class->_do_list_select( "board_id = ?", [$board_id] );
}


#
#                                                                         ______________________________ 
#                                                                        /                              \
# ---------------------------------------------------------------------- | Getters/Setters               |
#                                                                        \______________________________/
#
sub id {
    # my ($self, $id) = @_;
    # $self->{id} = $id if defined $id;
    my $self = shift;
    return $self->{id};
}
sub name {
    my ($self, $name) = @_;
    $self->set ( 'name', $name ) if defined $name;
    return $self->{name};  
}
sub sortkey {
    my ($self, $sortkey) = @_;
    $self->set ( 'sortkey', $sortkey ) if defined $sortkey;
    return $self->{sortkey};  
}
sub description {
    my ($self, $description) = @_;
    $self->set ( 'description', $description ) if defined $description; 
    return $self->{description};  
}
sub namedquery_name {
    my ($self, $namedquery_name) = @_;
    $self->set ( 'namedquery_name', $namedquery_name ) if defined $namedquery_name;
    return $self->{namedquery_name};
}
sub namedquery_sharer_id {
    my ($self, $namedquery_sharer_id) = @_;
    $self->set ( 'namedquery_sharer_id', $namedquery_sharer_id ) if defined $namedquery_sharer_id;
    return $self->{namedquery_sharer_id};
}
sub board_id {
    my ($self, $board_id) = @_;
    $self->set ( 'board_id', $board_id ) if defined $board_id;
    return $self->{board_id}; 
}
sub wip_warning_threshold {
    my ($self, $wip_warning_threshold) = @_;
    $self->set ( 'wip_warning_threshold', $wip_warning_threshold ) if defined $wip_warning_threshold;
    return $self->{wip_warning_threshold}; 
}
sub wip_overload_threshold {
    my ($self, $wip_overload_threshold) = @_;
    $self->set ( 'wip_overload_threshold', $wip_overload_threshold ) if defined $wip_overload_threshold;
    return $self->{wip_overload_threshold}; 
}
sub space_occupied {
    my ($self, $space_occupied) = @_;
    $self->set ( 'space_occupied', $space_occupied ) if defined $space_occupied;
    return $self->{space_occupied};
}
sub color {
    my ($self, $color) = @_;
    $self->set ( 'color', $color ) if defined $color;
    return $self->{color};  
}



sub color_type {
    
    my $self = shift;
    my $color = shift;
    
    #
    # If we pass a value for $color we want the leading dot of for the CSS class name back if the color is a CSS class
    my $keepdot = ($color)?"1":"0";
    
    $color = ($self->{color}) unless defined $color;
    $color = trim( $color );
    
    my $type;
    my $value;

    my $HEX  = '#[0..9A..Fa..f]{6}|[0..9A..Fa..f]{3}';
    my $RGB  =  'rgb\s*\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*\)';
    my $RGBA = 'rgba\s*\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(0?)(\.\d+)\s*\)';
    
    #
    # assume that color's value is always trimmed ... 
    for ( $color ) {
        /^([\.](\w+))\s*.*$/        && do {$type = "CSS Class";     $value = ($keepdot)?".$2":$2;   last; };
        /^($HEX)\s*.*$/             && do {$type = "CSS Color";     $value = $1;                    last; };
        /^($RGBA)\s*.*$/            && do {$type = "CSS Color";     $value = "rgba($2,$3,$4,0$6)";  last; };
        /^($RGB)\s*.*$/             && do {$type = "CSS Color";     $value = "rgb($2,$3,$4)";       last; };
        /^(\w+)\s*.*$/              && do {$type = "CSS Colorname"; $value = $1;                    last; };
        do { $type = "CSS Colorname"; $value="LightGray";                                           last; }
    }
    
    return { type=>$type, value=>$value };
}

sub space_occupied_text {
    my $self = shift;

    my $space = $self->space_occupied || return undef;
    
    ( $space==2 ) && return 'double';
    ( $space==3 ) && return 'triple';

    return '---';
}

#
#                                                                         ______________________________ 
#                                                                        /                              \
# ---------------------------------------------------------------------- | Fluent Setters                |
#                                                                        \______________________________/
#
sub with_color {
    my ($self, $color) = @_;
    
    $self->{color} = $color if defined $color;
    return $self;  
}


sub with_query {
    my $self = shift;
    my $queryName = shift;
    
    $self->{queryName} = $queryName;
    return $self;
}

#
#                                                                         ______________________________ 
#                                                                        /                              \
# ---------------------------------------------------------------------- | Validators                    |
#                                                                        \______________________________/
#
sub _check_name {
    my ($invocant, $name) = @_;
    $name = trim($name);
    $name || ThrowUserError('pambaan_lane_blank_name');

    if (length($name) > PAMBAAN_MAX_LANE_SIZE) {
        ThrowUserError('pambaan_lane_name_too_long', {'name' => $name, 'namelimit' => PAMBAAN_MAX_LANE_SIZE});
    }
    return $name;
}

sub _check_threshold {
    my ($invocant, $threshold, $field) = @_;

    return undef unless $threshold; # will hopefully convert 0 to NULL
    
    my $tainttest = $threshold;
    ThrowUserError( 'pambaan_lane_must_be_numeric',  {'field'=>$field, 'value' => $threshold} )  unless ( detaint_signed( $tainttest ) );
    
    $threshold = int( $threshold );
    ThrowUserError( 'pambaan_lane_must_be_positive', {'field'=>$field, 'value' => $threshold} ) unless ( $threshold >= 0 );

    $threshold = undef unless $threshold;
    return $threshold;

}

sub _check_color {
    my ($invocant, $color) = @_;
    
    $color = $invocant->color_type($color)->{value};
    
    return $color;
}

sub _check_space_occupied {
    my ($invocant, $space_occupied, $field ) = @_;
    
    return undef unless $space_occupied;

    my $tainttest = $space_occupied;
    ThrowUserError( 'pambaan_lane_must_be_numeric',  {'field'=>$field, 'value' => $space_occupied} )  unless ( detaint_natural( $tainttest ) );
    
    $space_occupied = ($space_occupied > 3)?3:$space_occupied;
    return $space_occupied;
}


#
#                                                                         ______________________________ 
#                                                                        /                              \
# ---------------------------------------------------------------------- | Business Beef                 |
#                                                                        \______________________________/
#
sub _LookupNamedQuery {
        my ($self, $name, $sharer_id ) = @_;

       
        Bugzilla->login(LOGIN_REQUIRED);
        $sharer_id ||= 1;
        my $query = Bugzilla::Search::Saved->check(
            { user => $sharer_id, name => $name }
            );

        $query->url
           || ThrowUserError("buglist_parameters_required");

        # Detaint $sharer_id.
        return wantarray ? ( $query->url, $query->id ) : $query->url;
}

sub query_statement {
    my $self = shift;
    
    my $namedQueryName = $self->{namedquery_name}           || ThrowUserError("pambaan_no_query_name");
    my $namedQuerySharerId = $self->{namedquery_sharer_id}  || ThrowUserError("pambaan_no_sharer_id");
    
    my ( $buffer, $query_id ) = $self->_LookupNamedQuery( $namedQueryName, $namedQuerySharerId );
    
    my $params = new Bugzilla::CGI( $buffer );
        
    my $search = new Bugzilla::Extension::PAMBAAN::Search( 'fields' => BUGLIST_SELECTCOLUMNS, 
                                                           'params' => scalar $params->Vars,
                                                           'order'  => BUGLIST_ORDERSTRINGS,
                                                           'sharer' => $self->{sharer_id}
                                                         );

    my $bz_version = Bugzilla::Constants::BUGZILLA_VERSION;    
    
    $search->search_description;
    return $search->{sql};
}


sub bugcount {
    my $self = shift;
    return scalar @{$self->bugs()};
}

sub is_overload {
    my $self = shift;

    return 0 unless $self->wip_overload_threshold;
    return ($self->bugcount >= $self->wip_overload_threshold)?1:0;
}

sub is_warning {
    my $self = shift;
    
    return 0 unless $self->wip_warning_threshold;
    return ($self->bugcount >= $self->wip_warning_threshold && !$self->is_overload)?1:0;
}

sub test_work_in_progress {
    my $self = shift;
    
    warn "\n\n", __PACKAGE__, "::test_work_in_progress ", $self->name, " is_warning? [", $self->is_warning, "]", "\n";
    warn         __PACKAGE__, "::test_work_in_progress ", $self->name, " is_overload? [", $self->is_overload, "]", "\n";    
}

sub has_bugs {
    my $self = shift;
    return $self->bugcount > 0;
}




sub bugs {
    my $self = shift;
    
    if ( $self->{bugs} ) {
        return $self->{bugs};
    }
    my $statement = $self->query_statement;
    
    # Connect to the shadow database if this installation is using one to improve
    # query performance.
    my $dbh = Bugzilla->switch_to_shadow_db();

    # Normally, we ignore SIGTERM and SIGPIPE, but we need to
    # respond to them here to prevent someone DOSing us by reloading a query
    # a large number of times.
    local $::SIG{TERM} = 'DEFAULT';
    local $::SIG{PIPE} = 'DEFAULT';

    # Execute the query.
    
    my $buglist_sth = $dbh->prepare( $statement );
    $buglist_sth->execute();
    
    my @bugs = ();
    while ( my $hash_ref = $buglist_sth->fetchrow_hashref() ) {
        push @bugs, $hash_ref;
    }
    $buglist_sth->finish();

    Bugzilla->switch_to_main_db();

    $self->{bugs} = \@bugs;
    return $self->{bugs};

}


1;
__END__


=head1 NAME

Bugzilla::Extension::PAMBAAN::Board.

Based on L<Bugzilla::Object>.

=head1 DESCRIPTION

Bugzilla::Extension::PAMBAAN::Lane represents a lane in your Bugzilla::Extension::PAMBAAN::Board.

=head1 SYNOPSIS

=head2 Transient Instances

 
    use Bugzilla::Extension::PAMBAAN::Lane;
    
    sub someMethod{
        my $adminuser = new Bugzialla::User( "admin@mydomain.tld" );
        my $lane = Bugzilla::Extension::PAMBAAN::Lane->transientnew( 
            {
                name                    =>  "First", 
                description             =>  "First Lane", 
                namedquery_name         =>  "Populate with UNCONFIRMED"
                namedquery_sharer_id    =>  $adminuser->id()
                board_id                =>  undef
                color                   => "rgba(127,127,196,0.3)"
                sortkey                 => 10
            }
        );
    }


=head2 Persistent Instances


    use Bugzilla::Extension::PAMBAAN::Lane;
    
    sub someMethod{
        my $adminuser = new Bugzialla::User( "admin@mydomain.tld" );
        my $board = new Bugzilla::Extension::PAMBAAN::Board( "First Board");
        
        my $lane1 = Bugzilla::Extension::PAMBAAN::Lane->create( 
            {
                name                    =>  "First", 
                description             =>  "First Lane", 
                namedquery_name         =>  "Populate with UNCONFIRMED"
                namedquery_sharer_id    =>  $adminuser->id()
                board_id                =>  $board->id()            # Pass the board's ID directly
                color                   => "rgba(127,127,196,0.3)"
                sortkey                 => 10
            }
        );
        my $lane1 = Bugzilla::Extension::PAMBAAN::Lane->create( 
            {
                name                    =>  "First", 
                description             =>  "First Lane", 
                namedquery_name         =>  "Populate with UNCONFIRMED"
                namedquery_sharer_id    =>  $adminuser->id()
                board                   =>  $board                  # Pass the board as reference. Create will extract its ID
                color                   => "rgba(127,127,196,0.3)"
                sortkey                 => 10
            }
        );
        
    }


=head1 FIELDS


=head1 METHODS

=head2 PUBLIC Methods

=head2 PRIVATE Methods


=cut

