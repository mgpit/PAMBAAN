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

package Bugzilla::Extension::PAMBAAN;
use strict;

use base qw(Bugzilla::Extension Exporter);
our @EXPORT = qw();  
our $version="0.6.2";

use Bugzilla;
use Bugzilla::Error;
use Bugzilla::User::Setting;
use Bugzilla::Token;
use Bugzilla::Constants;
use Bugzilla::Util;
use Bugzilla::Extension;


use Bugzilla::Extension::PAMBAAN::Util;
use Bugzilla::Extension::PAMBAAN::Schema;
use Bugzilla::Extension::PAMBAAN::Board;
use Bugzilla::Extension::PAMBAAN::Lane;

use MIME::Base64 qw(decode_base64 encode_base64);
use Data::Dumper;


use constant IN_COMMAND_LINE => (Bugzilla->usage_mode == USAGE_MODE_CMDLINE) ? 1 : 0;

use constant _ID=>encode_base64( 'id' );
use constant _NAME=>encode_base64( 'name' );

use constant PAGE_HANDLERS => {
    'pambaan/pambaanboard.html' => \&_do_display_pambaanboard,
    'pambaan/boards.html'       => \&_do_admin_listboards,
    'pambaan/editboard.html'    => \&_do_admin_editboard,
    'pambaan/lanes.html'        => \&_do_admin_listlanes,
    'pambaan/editlane.html'     => \&_do_admin_editlane,
    'pambaan/groups.html'       => \&_do_admin_editgroups,
};

BEGIN {
   *Bugzilla::Bug::has_blockers     = \&_bug_has_blockers;
   *Bugzilla::Bug::has_no_blockers  = \&_bug_has_no_blockers;
   *Bugzilla::Bug::is_blocker       = \&_bug_is_blocker;
   *Bugzilla::Bug::is_no_blocker    = \&_bug_is_no_blocker;
   *Bugzilla::Bug::current_estimate = \&_bug_current_estimate;
   *Bugzilla::Bug::gain             = \&_bug_gain;
   *Bugzilla::Bug::velocity         = \&_bug_velocity;
}

sub _bug_has_blockers {
    my $self = shift;
    return ($self->{dependantslist})?1:0;
}

sub _bug_has_no_blockers {
    my $self = shift;
    return not $self->has_blockers;
}

sub _bug_is_blocker {
    my $self = shift;
    return ($self->{blockinglist})?1:0;
}

sub _bug_is_no_blocker {
    my $self = shift;
    return not $self->is_blocker;
}

sub _bug_current_estimate {
    my $self = shift;
    return $self->actual_time+$self->remaining_time;
}

sub _bug_gain {
    my $self = shift;
    return $self->estimated_time - $self->current_estimate;
}

sub _bug_velocity {
    my $self = shift;
    my $velocity = undef;

    my $estimated_time = $self->estimated_time || 0;
    if ( $estimated_time > 0 ) {
        my $percentage = ( $self->current_estimate / $self->estimated_time ) * 100;
        $velocity = ( $percentage > 0 )?int($percentage + $percentage/abs($percentage*2)):undef;
    }
    
    return $velocity;
}



#
#                                                                         ______________________________ 
#                                                                        /                              \
# ---------------------------------------------------------------------- | Processing Hooks              |
#                                                                        \______________________________/
#

#
# ---------------------------------------- ||| Pambaan Board Display |||
#

sub _do_display_pambaanboard {
    return if !allowed_for_pambaan();

    my ($self, $args) = @_;   
    my ($vars) = @$args{qw(vars)};

    my $cgi = Bugzilla->cgi;
    my $params = $cgi->param;
    
    my $namekey = _NAME; my $idkey = _ID;

    $vars->{cgi_variables} = { $cgi->Vars };
    $vars->{cgi_parameters} = $params;
    
    
    # my @boards = Bugzilla::Extension::PAMBAAN::Board->get_all( {with_lanes => 1} );
    my @boards = Bugzilla::Extension::PAMBAAN::Board->get_all_accessible( {with_lanes => 1} );

    my $action = trim( $cgi->param('action') ) || '';
    my $new_board_id = trim( $cgi->param('current_board_id') ) || '' if ( defined $action && $action eq 'changeboard' );


    if ( !defined $new_board_id ) {
        my %pambaan_last_board = $cgi->cookie('pambaan_last_board');
        $new_board_id = decode_base64($pambaan_last_board{${idkey}}) if (%pambaan_last_board);
    }

    my $board;
    if ( $new_board_id ) {
        # Yes, do the iteration method ...
        foreach my $bb (@boards) {
            if ( $bb->id() == $new_board_id ) {
                $board = $bb;
                last;
            }
        }
    }
    
    # Take the first board retrieved by the database if we have no previous board
    # or the previous board is not accessible any more ...
    $board = ${boards}[0] unless defined $board;

    my @global_boards;
    my @personal_boards;
    foreach my $board ( @boards ) {
        my $boardshort = {"id"=>$board->id(), "name"=>$board->name()};
        if ($board->is_global) {
            push @global_boards, $boardshort;
        } else {
            push @personal_boards, $boardshort;
        }
    }
    my $pambaan_boards;
    $pambaan_boards->{global} = \@global_boards if scalar @global_boards;
    $pambaan_boards->{personal} = \@personal_boards if scalar @personal_boards;
    
    
    $vars->{all_pambaan_boards} = $pambaan_boards;
    $vars->{current_pambaan_board} = $board;
    
    my %cookieargs = ('-expires' => 'Fri, 01-Jan-2038 00:00:00 GMT' );
    my $cookie = {$namekey=>encode_base64($board->{name}), $idkey=>encode_base64($board->{id})};
    $cgi->send_cookie( -name => "pambaan_last_board", -value => $cookie, %cookieargs ) if defined $board->{name};        
}


#
# ---------------------------------------- ||| Pambaan Board Admin |||
#

sub _admin_prolog {
    my ($self, $args) = @_;   
    my ($vars) = @$args{qw(vars)};
    my $cgi = Bugzilla->cgi;

    my $user = Bugzilla->login( LOGIN_REQUIRED );
    $user->in_group( 'admin' ) || ThrowUserError('auth_failure', {action => 'edit', object => 'administrative_pages'});  

    my $action = trim( $cgi->param('action') )     || '';
    my $board_id = trim( $cgi->param('board_id') ) || '';
    my $lane_id = trim( $cgi->param('lane_id') )   || '';
    my $token = $cgi->param('token');

    return ( $action, $token, $board_id, $lane_id );
}

sub _capture_board {

    my ($self, $board, $vars) = @_;
    
    foreach my $field ( qw( name description blocked_bugs_handling restrict_to_assignee_currusr ) ) {
        my $value = $vars->{$field} || ''; # reset if form field blank
        trick_taint( $value );
        $board->$field( $value );
    }

   foreach my $field ( qw( defaultBoard ) ) {
        my $fieldvalue = $vars->{$field} || 0; # reset if form field blank
        my $value = $fieldvalue?1:0;
        # trick_taint( $value );
        $board->$field( $value );
    }
    

    return $board;
}

sub _capture_lane {
    my ($self, $lane, $vars) = @_;
    
    foreach my $field ( qw( name description color sortkey board_id wip_warning_threshold wip_overload_threshold space_occupied restrict_to_assignee_currusr ) ) {
        my $value = $vars->{"lane_$field"} || ''; # reset if form field blank
        trick_taint( $value );
        $lane->$field( $value );
    }
    foreach my $field ( qw( card_show_asignee card_show_importance card_show_product card_show_bug_status card_show_timetracking  ) ) {
        my $fieldvalue = $vars->{"lane_$field"} || 0; # reset if form field blank
        my $value = $fieldvalue?1:0;
        # trick_taint( $value );
        $lane->$field( $value );
    }
    foreach my $field ( qw( namedquery_name_and_sharer_id ) ) {
        my $value = $vars->{"lane_$field"};
        if ( $value ) {
            trick_taint( $value );
            my ($namedquery_name, $namedquery_sharer_id) = eval( $value );
            $lane->namedquery_sharer_id( $namedquery_sharer_id );
            $lane->namedquery_name( $namedquery_name );
        }
    }
    
    return $lane;
}

sub _do_pambaan_shared_searches {
    my ( $self, $vars ) = @_;
    my $user = Bugzilla->user;

    my @queries = (@{$user->queries}, @{$user->queries_available});
    
    my @pambaan_shared_searches = grep { my $srch = $_->shared_with_group();
                                         (defined $srch) ? $srch->{name} eq 'pambaan' : 0 } @queries; 
    
    return \@pambaan_shared_searches;
}



#
# ---------------------------------------- ||| Pambaan Board Admin - Lanes |||
#

sub _do_admin_editlane {
    my $self = shift;
    my ($action, $token, $board_id, $lane_id) = $self->_admin_prolog( @_ );
    
    my ($args) = @_;   
    my ($vars) = @$args{qw(vars)};

    my $cgi = Bugzilla->cgi;
    my $cgi_vars = $cgi->Vars;

    my $board = new Bugzilla::Extension::PAMBAAN::Board( $board_id );
    ThrowUserError( 'pambaan_no_pambaan_board' ) unless $board;
       
    my $lane;
    if ( $action && $board_id ) {
        SWITCH: {
            $vars->{action} = $action;
            ($action eq 'editlane' )   && do { $lane = (defined $lane_id)
                                                     ? new Bugzilla::Extension::PAMBAAN::Lane( $lane_id )
                                                     : transientnew Bugzilla::Extension::PAMBAAN::Lane( "Error!!!" );
                                                $vars->{token} = issue_session_token( 'editlane' );
                                                last SWITCH;                                 
                                             };
            ($action eq 'newlane')     && do { $board->fetch_lanes;
                                               $lane = Bugzilla::Extension::PAMBAAN::Lane->NEWTEMPLATE;
                                               $lane->board_id( $board->id );
                                               $lane->sortkey( (($board->number_of_lanes)+1)*10 );
                                               $vars->{token} = issue_session_token( 'newlane' );
                                               last SWITCH;
                                             };                                            
        }
        $vars->{pambaan_lane} = $lane;
        $vars->{pambaan_shared_searches} = $self->_do_pambaan_shared_searches;                                                 
    }    

}

sub _do_admin_listlanes {
    my $self = shift;
    my ($action, $token, $board_id, $lane_id) = $self->_admin_prolog( @_ );
    
    my ($args) = @_;   
    my ($vars) = @$args{qw(vars)};

    my $cgi = Bugzilla->cgi;
    my $cgi_vars = $cgi->Vars;
    
    if ( $action && $action ne 'lanes' ) {
        SWITCH: {
            ( (    $action eq 'deletelane') 
                && $board_id && $lane_id    ) &&   do {     check_token_data( $token, 'deletelane' );
                                                            my $lane = new Bugzilla::Extension::PAMBAAN::Lane( $lane_id );
                                                            $lane->remove_from_db;
                                                            delete_token( $token );
                                                            last SWITCH; 
                                                      };
            ( (    $action eq 'updatelane') 
                && $board_id && $lane_id    ) &&   do {     check_token_data( $token, 'editlane' );
                                                            my $lane = new Bugzilla::Extension::PAMBAAN::Lane( $lane_id );
                                                            my $old = $lane;
                                                            if ( $lane ) {
                                                                $self->_capture_lane( $lane, $cgi_vars );
                                                                $lane->update;
                                                            }
                                                            delete_token( $token );
                                                            last SWITCH;
                                                      };
                                                      
            ( (    $action eq 'addlane') 
                && $board_id && !$lane_id   ) &&   do {     check_token_data( $token, 'newlane' );
                                                            my $lane = transientnew Bugzilla::Extension::PAMBAAN::Lane( "New Lane" );
                                                            $self->_capture_lane( $lane, $cgi_vars );
                                                            Bugzilla::Extension::PAMBAAN::Lane->create( $lane );
                                                            delete_token( $token );
                                                            last SWITCH;
                                                       };                                                      
            { last SWITCH; };
        }
        #
        # In editlane.html the form's action points to pambaan/lanes.html and not to a page confirming the insert/update.
        #   This behaviour differs from standard Bugzilla screen flow but I consider this as the most likely use case. 
        # Users are likely to refresh this view with F5 which would result in the annoying
        # question I he/she wants to repost the data again. So issue a redirect to pambaan/lanes.html.
        my $urlbase = correct_urlbase();
        print $cgi->redirect(-uri => "${urlbase}page.cgi?id=pambaan/lanes.html&board_id=${board_id}" ) unless $action eq 'lanes';
        return;
    }
    
    my $board = new Bugzilla::Extension::PAMBAAN::Board( {id=>$board_id, with_lanes=>1} );
    $vars->{pambaan_board} = $board;
    $vars->{token} = issue_session_token( 'deletelane' );
                                                              
}

#
# ---------------------------------------- ||| Pambaan Board Admin - Group Access |||
#

sub __multiselect_field {
    my ( $self, $arg ) = @_;

    if ( $arg ) {
    
        return $arg if ref( $arg );
        
        my @ary;
        push @ary, $arg;
        return \@ary;
    }

    return undef;
}

sub _do_admin_editgroups {
    my $self = shift;
    my ($action, $token, $board_id, $lane_id) = $self->_admin_prolog( @_ );
    
    my ($args) = @_;   
    my ($vars) = @$args{qw(vars)};

    my $cgi = Bugzilla->cgi;
    my $cgi_vars = $cgi->Vars;

    my $board = new Bugzilla::Extension::PAMBAAN::Board( {id=>$board_id, with_lanes=>1} );
    
    if ( $action && $action eq 'updategroups' ) {
            check_token_data( $token, 'updategroups' );
            # Some fuzz with mulitselect values ...
            my $selected_for_adding   = $self->__multiselect_field( $cgi_vars->{pambaan_board_groups_available} );
            my $selected_for_removing = $self->__multiselect_field( $cgi_vars->{pambaan_board_groups_assigned}  );
            
            $board->update_groups( {'add' => $selected_for_adding, 'remove' => $selected_for_removing } );
            delete_token( $token );
    }
    my ( $groups_assigned, $groups_assigned_ids ) = $board->groups;
    push @$groups_assigned_ids, -1; # if no groups are assigned than the in clause would be: IN ( ) 

    my $group_ids_string = join(",", @$groups_assigned_ids );
    # fetcht the other groups
    # don't need an ORDER BY as new_from_list will rely on $Bugzilla::Group::LIST_ORDER
    my $sql = <<"EOSQL";
SELECT g.id 
  FROM groups g
 WHERE g.id NOT IN ( $group_ids_string )
EOSQL

    my $dbh = Bugzilla->dbh;
    my $remaining_group_ids = $dbh->selectcol_arrayref( $sql, undef );
    my $groups_not_assigned = Bugzilla::Group->new_from_list($remaining_group_ids);
    
    $vars->{groups_assigned} = $groups_assigned || [];
    $vars->{groups_not_assigned} = $groups_not_assigned || [];
    $vars->{pambaan_board} = $board;
    $vars->{token} = issue_session_token( 'updategroups' );

}



#
# ---------------------------------------- ||| Pambaan Board Admin - Boards |||
#

sub _do_admin_editboard {
    my $self = shift;
    my ($action, $token, $board_id, $lane_id) = $self->_admin_prolog( @_ );
    
    my ($args) = @_;   
    my ($vars) = @$args{qw(vars)};

    my $cgi = Bugzilla->cgi;
    my $cgi_vars = $cgi->Vars;

    my $board;
    if ( $action ) {
        $vars->{action} = $action;
        SWITCH: {
            ($action eq 'editboard' )   && do { $board = new Bugzilla::Extension::PAMBAAN::Board( {id=>$board_id, with_lanes=>1} );
                                                $vars->{pambaan_board} = $board;
                                                $vars->{token} = issue_session_token( 'editboard' );
                                                last SWITCH;                                 
                                              };
            ($action eq 'newboard')     && do { $board = Bugzilla::Extension::PAMBAAN::Board->NEWTEMPLATE;
                                                $vars->{pambaan_board} = $board;
                                                #
                                                # Create a dummy lane for quick editing the board's fist lane ...
                                                my $lane = Bugzilla::Extension::PAMBAAN::Lane->NEWTEMPLATE;
                                                $lane->description( "This will be the board's first lane" );
                                                $vars->{pambaan_lane} = $lane;
                                                $vars->{pambaan_shared_searches} = $self->_do_pambaan_shared_searches;
                                                $vars->{token} = issue_session_token( 'newboard' );
                                                last SWITCH;
                                              };                                                                                         
        }
    
    }    

}

sub _do_admin_listboards{
    my $self = shift;
    my ($action, $token, $board_id, $lane_id) = $self->_admin_prolog( @_ );
    
    my ($args) = @_;   
    my ($vars) = @$args{qw(vars)};

    my $cgi = Bugzilla->cgi;
    my $cgi_vars = $cgi->Vars;
        
    if ( $action ) {
        SWITCH: {
            ( (    $action eq 'deleteboard') 
                && $board_id                 ) &&   do {    check_token_data( $token, 'deleteboard' );
                                                            my $board = new Bugzilla::Extension::PAMBAAN::Board( {id=>$board_id} );
                                                            $board->remove_from_db;
                                                            delete_token( $token );
                                                            last SWITCH; 
                                                       };
            ( (    $action eq 'updateboard'
                && $board_id )               ) &&   do {    check_token_data( $token, 'editboard' );
                                                            my $board = new Bugzilla::Extension::PAMBAAN::Board( {id=>$board_id} );
                                                            # Won't use set_all() ... 
                                                            my $old = $board;
                                                            if ( $board ) {
                                                                $self->_capture_board( $board, $cgi_vars );
                                                                $board->update;
                                                            }
                                                            delete_token( $token );
                                                            last SWITCH;
                                                       };
            ($action eq 'addboard')           &&    do {    check_token_data( $token, 'newboard' );
                                                            my $dbh = Bugzilla->dbh;
                                                            # Must wrap creation of board an lane in transaction.
                                                            # Else any errors in creating the lane will leave a board without lane.
                                                            $dbh->bz_start_transaction();
                                                                my $board = Bugzilla::Extension::PAMBAAN::Board->NEWTEMPLATE;
                                                                $self->_capture_board( $board, $cgi_vars );
                                                                $board = Bugzilla::Extension::PAMBAAN::Board->create( $board );
                                                                
                                                                my $lane = Bugzilla::Extension::PAMBAAN::Lane->NEWTEMPLATE;
                                                                $self->_capture_lane( $lane, $cgi_vars );
                                                                # won't allow a lane without a name
                                                                # don't want to run in validation
                                                                if ( defined $lane->name() && $lane->name() ne "" ) {
                                                                    $lane->board_id( $board->id );
                                                                    Bugzilla::Extension::PAMBAAN::Lane->create( $lane );
                                                                }
                                                            $dbh->bz_commit_transaction();
                                                            
                                                            delete_token( $token );
                                                            last SWITCH;
                                                       };
            { last SWITCH; };
        }
        #
        # In editboard.html the form's action points to pambaan/boards.html and not to a page confirming the insert/update.
        #   This behaviour differs from standard Bugzilla screen flow but I consider this as the most likely use case. 
        # Users are likely to refresh this view with F5 which would result in the annoying
        # question I he/she wants to repost the data again. So issue a redirect to pambaan/boards.html.
        my $urlbase = correct_urlbase();
        print $cgi->redirect(-uri => "${urlbase}page.cgi?id=pambaan/boards.html" );
        return;
    }

    my @boards = Bugzilla::Extension::PAMBAAN::Board->get_all( {with_lanes=>1} ); # Should consider this ..
    $vars->{all_pambaan_boards} = \@boards;
    $vars->{token} = issue_session_token( 'deleteboard' );
}

sub page_before_template {
    my $self = shift;
    my ($args) = @_;   
    my ($page) = @$args{qw(page_id)};

    warn __PACKAGE__,": Got Page $page ..........", "\n";
    my $cgi = Bugzilla->cgi;
    my $token = $cgi->param('token');

        
      
    my $pagehandler = PAGE_HANDLERS->{$page};
    warn __PACKAGE__,": Handling $page ..........", "\n" if defined $pagehandler;
    $self->$pagehandler( @_ ) if defined $pagehandler;
        
}



#
#                                                                         ______________________________ 
#                                                                        /                              \
# ---------------------------------------------------------------------- | Installation Hooks            |
#                                                                        \______________________________/
#

sub db_schema_abstract_schema {
    my ($self, $args) = @_;
    ## print "db_schema_abstract_schema hook\n" unless $args->{silent};
        
    pambaan_schema_init($args->{schema});
}

sub install_update_db {
    my ($self, $args) = @_;
    ## print "install_update_db hook\n" unless $args->{silent};
 
    pambaan_do_schema_updates;
}

sub install_before_final_checks {
    my ($self, $args) = @_;
    ## print "Install-before_final_checks hook\n" unless $args->{silent};

    add_setting( 'board_chooser', [ 'default', 'last', 'none' ], 'last' );
    
    # To add descriptions for the setting and choices, add extra values to 
    # the hash defined in global/setting-descs.none.tmpl. Do this in a hook: 
    # hook/global/setting-descs-settings.none.tmpl .
}


__PACKAGE__->NAME;
