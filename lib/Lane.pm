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

our $version="0.6.2";

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

use constant VALID_COLUMNS => qw( id 
                                  name 
                                  sortkey 
                                  description 
                                  namedquery_name 
                                  namedquery_sharer_id 
                                  board_id 
                                  wip_warning_threshold 
                                  wip_overload_threshold 
                                  space_occupied color
                                  card_show_asignee
                                  card_show_importance
                                  card_show_product
                                  card_show_bug_status
                                  card_show_timetracking
                                  restrict_to_assignee_currusr
                                );


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
    card_show_asignee
    card_show_importance
    card_show_product
    card_show_bug_status
    card_show_timetracking   
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
    card_show_asignee
    card_show_importance
    card_show_product
    card_show_bug_status
    card_show_timetracking
    restrict_to_assignee_currusr
);

use constant NAME_FIELD => 'name';
use constant ID_FIELD   => 'id';
use constant LIST_ORDER => 'board_id, sortkey';
use constant VALIDATORS =>  {
                                name                            => \&_check_name,
                                wip_warning_threshold           => \&_check_threshold,
                                wip_overload_threshold          => \&_check_threshold,
                                color                           => \&_check_color,
                                space_occupied                  => \&_check_space_occupied,
                                card_show_asignee               => \&Bugzilla::Object::check_boolean,
                                card_show_importance            => \&Bugzilla::Object::check_boolean,
                                card_show_product               => \&Bugzilla::Object::check_boolean,
                                card_show_bug_status            => \&Bugzilla::Object::check_boolean,
                                card_show_timetracking          => \&Bugzilla::Object::check_boolean,
                                restrict_to_assignee_currentusr => \&_check_yes_no_empty,                                
                            };

use constant PAMBAAN_MAX_LANE_SIZE => 127;                            

use constant BUGLIST_SELECTCOLUMNS => qw ( bug_id  bug_severity short_desc priority bug_status product component assigned_to_realname assigned_to );
use constant DEPENDENCY_COLUMNS    => qw ( dependantslist blockinglist );
use constant TIMETRACKING_COLUMNS  => qw ( estimated_time remaining_time actual_time percentage_complete deadline );
use constant BUGLIST_ORDERSTRINGS  => [ "bug_severity", "bug_id" ];

use constant NEWTEMPLATE => bless( {
    name => "New Lane", 
    description => "Another Lane",
    card_show_asignee => 1,
    card_show_importance => 1,
    card_show_product => 1,
    card_show_bug_status => 1,
    card_show_timetracking => 0,
    sortkey => 10,
}, 'Bugzilla::Extension::PAMBAAN::Lane' );

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
    $self->set ( 'description', (trim($description) eq '')?undef:trim($description) ) if defined $description; 
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

sub restrict_to_assignee_currusr {
    my ( $self, $restrict_to_assignee_currusr ) = @_;    
    $self->set ( 'restrict_to_assignee_currusr', (trim($restrict_to_assignee_currusr) eq '')?undef:trim($restrict_to_assignee_currusr) ) if defined $restrict_to_assignee_currusr; 
    return $self->{restrict_to_assignee_currusr};
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

sub card_show_asignee {
    my ($self, $card_show_asignee ) = @_;
    $self->set( 'card_show_asignee', $card_show_asignee ) if defined $card_show_asignee;
    return $self->{card_show_asignee};
}

sub card_show_importance {
    my ($self, $card_show_importance ) = @_;
    $self->set( 'card_show_importance', $card_show_importance ) if defined $card_show_importance;
    return $self->{card_show_importance};
}

sub card_show_product {
    my ($self, $card_show_product ) = @_;
    $self->set( 'card_show_product', $card_show_product ) if defined $card_show_product;
    return $self->{card_show_product};
}

sub card_show_bug_status {
    my ($self, $card_show_bug_status ) = @_;
    $self->set( 'card_show_bug_status', $card_show_bug_status ) if defined $card_show_bug_status;
    return $self->{card_show_bug_status};
}

sub card_show_timetracking {
    my ($self, $card_show_timetracking ) = @_;
    $self->set( 'card_show_timetracking', $card_show_timetracking ) if defined $card_show_timetracking;
    return $self->{card_show_timetracking};
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

sub _check_yes_no_empty {
    my ($invocant, $yes_no_empty, $field ) = @_;
    
    return undef unless $yes_no_empty;
    return undef if trim($yes_no_empty) eq '';
    
    my $yes_no = uc( $yes_no_empty );
    return $yes_no if ( $yes_no =~ /Y|N/ );

    ThrowUserError('pambaan_invalid_field_value', {'field' => $field, 'value' => $yes_no, 'allowedvalues' => [ 'Y', 'N' ], 'allowempty' => 1} );
}


#
#                                                                         ______________________________ 
#                                                                        /                              \
# ---------------------------------------------------------------------- | Business Beef                 |
#                                                                        \______________________________/
#

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


sub has_bugs {
    my $self = shift;
    return $self->bugcount > 0;
}

sub board {
    my $self = shift;
    
    $self->{board} = new Bugzilla::Extension::PAMBAAN::Board( $self->board_id() ) unless $self->{board};
    return $self->{board};
}

sub wants_blocked_bugs_hidden {
    my $self = shift;
    return $self->board->wants_blocked_bugs_hidden;
}

sub wants_blocked_bugs_noncontributing {
    my $self = shift;
    return $self->board->wants_blocked_bugs_noncontributing;
}

sub wants_all_matching_bugs {
    my $self = shift;
    return $self->board->wants_all_matching_bugs;
}


sub is_global {
    my $self=shift;

    return $self->board->is_global unless $self->restrict_to_assignee_currusr;
    return ($self->restrict_to_assignee_currusr eq 'N')?1:0;
}
sub is_personal {
    my $self=shift;

    return $self->board->is_personal unless $self->restrict_to_assignee_currusr;
    return ($self->restrict_to_assignee_currusr eq 'Y')?1:0;
}



sub bugs {
    my $self = shift;
    
    if ( $self->{bugs} ) {
        return $self->{bugs};
    }
    
    $self->{bugs} = $self->_populate;
    return $self->{bugs};
}

sub bugcount {
    my $self = shift;
    return scalar @{$self->bugs};
}

sub allbugcount {
    my $self = shift;
    $self->_populate unless $self->bugs;
    return $self->{allbugcount};
}

sub bugs_hidden {
    my $self = shift;
    return 0 unless ($self->allbugcount > 0);
    
    return $self->allbugcount - $self->bugcount;
}

sub bugload {
    my $self = shift;
    $self->_populate unless $self->bugs;
    return $self->{bugload};
}

sub timeload {
    my $self = shift;
    $self->_populate unless $self->bugs;
    return $self->{timeload};
}

sub progress {
    my $self = shift;
    $self->_populate unless $self->bugs;
    return $self->{progress};
}

sub timeload_estimated {
    my $self = shift;
    $self->_populate unless $self->bugs;
    return $self->{timeload_estimated};
}

sub velocity {
    my $self = shift;
    my $velocity = undef;

    my $timeload_estimated = $self->timeload_estimated || 0;
    if ( $timeload_estimated > 0 ) {
        my $percentage = ( $self->current_estimate / $self->estimated_time ) * 100;
        $velocity = ( $percentage > 0 )?int($percentage + $percentage/abs($percentage*2)):undef;
    }
    
    return $velocity;
}


sub query_statement {
    my $self = shift;
    
    my $namedQueryName = $self->{namedquery_name}           || ThrowUserError("pambaan_no_query_name");
    my $namedQuerySharerId = $self->{namedquery_sharer_id}  || ThrowUserError("pambaan_no_sharer_id");
    
    my $user = Bugzilla->user;
    
    my @selectcolumns = BUGLIST_SELECTCOLUMNS;
    my $orderstrings = BUGLIST_ORDERSTRINGS;
    
    @selectcolumns = (@selectcolumns, TIMETRACKING_COLUMNS ) if $user->is_timetracker;
    my $board = $self->board;    
    
    if ( $board->wants_blocked_bugs_hidden || $board->wants_blocked_bugs_noncontributing ) {
        @selectcolumns = (@selectcolumns, DEPENDENCY_COLUMNS );
        unshift @$orderstrings, 'blocked';
    }
    
    
    
    my ( $buffer, $query_id ) = $self->_LookupNamedQuery( $namedQueryName, $namedQuerySharerId );
    my $params = new Bugzilla::CGI( $buffer );
        
    my $search = new Bugzilla::Extension::PAMBAAN::Search( 'fields' => \@selectcolumns, 
                                                           'params' => scalar $params->Vars,
                                                           'order'  => $orderstrings,
                                                           'sharer' => $self->{sharer_id},
                                                           'personal' => $self->is_personal,
                                                         );

    my $bz_version = Bugzilla::Constants::BUGZILLA_VERSION;    
    
    $search->search_description;
    
    return $search->{sql};
    
    
}

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

sub _populate {
    my $self = shift;
    my $statement = $self->query_statement;
    
    ### warn "\n\n", __PACKAGE__, "->_populate ", "Populating for [", $self->name, "]...", "\n";
    
    # Connect to the shadow database if this installation is using one to improve
    # query performance.
    my $dbh = Bugzilla->switch_to_shadow_db();

    # Comment copied from buglist.cgi ...
    # Normally, we ignore SIGTERM and SIGPIPE, but we need to respond to them here to prevent someone DOSing us 
    # by reloading a query a large number of times.
    $::SIG{TERM} = 'DEFAULT';
    $::SIG{PIPE} = 'DEFAULT';

    # Execute the query.
    
    my $buglist_sth = $dbh->prepare( $statement );
    $buglist_sth->execute();
    

    my $user = Bugzilla->user;

    my @bugs = ();
    my $timeload = 0;               # for counting the current timeload of the lane (in hrs.)
    my $timeload_estimated = 0;     # for counting the originally estimated timeload of the lane (in hrs.)
    my $progress = 0;               # the lane's overall progress of work done in percent
    my $allbugcount = 0;            # number of all the bugs returned by the lane's search
    my $bugload = 0;                # number of bugs contributing to the lane's bugload

    while ( my $hash_ref = $buglist_sth->fetchrow_hashref() ) {
        my $bug = bless( $hash_ref, 'Bugzilla::Bug' );  ## bless as bless can ...
        
        push @bugs, $bug unless $self->wants_blocked_bugs_hidden && $bug->has_blockers;
        $allbugcount++;

        if ( $self->wants_all_matching_bugs || $bug->has_no_blockers ) { 
            $bugload++ unless $self->wants_blocked_bugs_noncontributing && $bug->has_blockers;
            if ( $user->is_timetracker ) {
                $timeload += $bug->current_estimate;
                $timeload_estimated += $bug->estimated_time;
                $progress += $bug->actual_time;
            }
        } 
    }

    $buglist_sth->finish();

    # transient fields ... will not go into the database ... precomputed values ... could be considered dirrty
    $self->{bugload}            = $bugload;
    $self->{timeload}           = $timeload;
    $self->{progress}           = $progress;
    $self->{timeload_estimated} = $timeload_estimated;
    $self->{allbugcount}        = $allbugcount;

    Bugzilla->switch_to_main_db();
    
    return \@bugs;
}



1;
__END__


=head1 NAME

Bugzilla::Extension::PAMBAAN::Lane.

Based on L<Bugzilla::Object>.

=head1 DESCRIPTION

Bugzilla::Extension::PAMBAAN::Lane represents a lane in your C<Bugzilla::Extension::PAMBAAN::Board>

The lane is populated with bugs by a named query / saved search - so the lanes's content will vary over time.

With version 0.6.0 "blocked bugs handling" has been introduced for C<Bugzilla::Extension::PAMBAAN::Board>s. You can configure, if
your board

=over

=item
wants to display all bugs matching the criteria

=item
wants to display all bugs matching the criteria but let blocked bugs not contribute to the lane's workload - currently named
"non contributing mode"

=item
wants to display all bugs matching the criteria without those bugs which are blocked by others

=back

So a lane will have an C<allbugcount>, a C<bugcount> and a C<bugload> which may all be equal, or C<bugcount> or C<bugload> may be
less than C<allbugcount>, and C<bugload> again may be less than C<bugcount>. For details see the corresponding methods.



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

sub timeload {
    my $self = shift;
    $self->_populate unless $self->bugs;
    return $self->{timeload};
}


=head2 PUBLIC Methods

=head2 PRIVATE Methods

=head3 bugs

Return the list of bugs for this lane or an empty list.
The list will contain 
    
=over    

=item   
either all the bugs matching the lane's query criteria 
if the board is set up to display all bugs

=item
or all the bugs matching the lane's query critera 
if the board is set up to display blocked bugs non contributing

=item
or all the bugs mathing the lane's query criteria filtered for those bugs blocked by others 
if the board is set up to hide all blocked bugs

=back

=head3 bugcount 

Return the number of bugs for this lane returned by L</bugs>
Will be less or equal L</bugcount>

=head3 allbugcount

Return the number of bugs for this lane matching the lane's query criteria.
Will be greater or equla L</bugcount>.

=head3 bugs_hidden

Return true if some bugs are hidden.
Hidden means that blocked bugs have been filtered and L</bugcount> is less than L</sallbugcount>.

=head3 bugload

Return the number of bugs contributing to the lane's workload.
This will be less or equal L</bugcount> if the lane wants blocked bugs displayed non contributing.

=head3 timeload

Return the sum of the current estimated time of all the bugs contributing to the lane's workload. (see L</bugload>)

=head3 

Return the overall time worked on the lane's bugs.


=head3 timeload_estimated

Return the sum of the originally estimated time of all all the bugs contributing to the lane's workload. (see L</bugload>)


=head3 velocity 

Return the lane's overall velocity.
This will be the ratio of the current time estimate and the originally estimated time for the lane's bugs.

This value is a momentary snapshot, only.

=cut

