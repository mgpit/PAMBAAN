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

package Bugzilla::Extension::PAMBAAN::Board;
use strict;

our $version="0.2";

use base qw(Bugzilla::Object Exporter);
our @EXPORT = qw();   


use Data::Dumper;
use Scalar::Util qw( blessed );

use Bugzilla::Constants;
use Bugzilla::Util qw( detaint_natural trim );
use Bugzilla::Error;


use Bugzilla::Extension::PAMBAAN::Lane;

use constant DB_TABLE => 'pambaan_boards';

use constant DEFAULTBOARD => {
    name => "Default", 
    description => "Default Board",
    defaultBoard => 1,
};

use constant VALID_COLUMNS => qw( id name description defaultBoard );

sub DB_COLUMNS {
    my $t = DB_TABLE;
    my @columns = map{ "$t.$_" } VALID_COLUMNS;
    return @columns;
 
};

use constant NUMERIC_COLUMNS => (
    'id',
    'defaultBoard',
);

use constant UPDATE_COLUMNS => (
    'name',
    'description',
    'defaultBoard',
);

use constant NAME_FIELD => 'name';
use constant ID_FIELD   => 'id';
use constant LIST_ORDER => 'id';
use constant VALIDATORS =>  {
                                defaultBoard    => \&Bugzilla::Object::check_boolean,
                                name            => \&_check_name,
                                description    => \&_check_description,
                            };

use constant PAMBAAN_MAX_BOARD_SIZE => 127;

sub new {
    my $invocant = shift;
    my $params = shift;
    my $class = ref($invocant) || $invocant;
    
    my $with_lanes = delete $params->{with_lanes} if ref( $params ) eq 'HASH';

    my $self = $class->SUPER::new($params);
    if ($self) {
        ### $self->{user} = $user if blessed $user;

        # Some DBs (read: Oracle) incorrectly mark the query string as UTF-8
        # when it's coming out of the database, even though it has no UTF-8
        # characters in it, which prevents Bugzilla::CGI from later reading
        # it correctly.
        utf8::downgrade($self->{query}) if utf8::is_utf8($self->{query});
    
        $self->_add_lanes if $with_lanes;
    }
    
    return $self;
}

sub create {
    my ($class, $params) = @_;
    my $dbh = Bugzilla->dbh;

    $dbh->bz_start_transaction();
    
    if ( $params->{defaultBoard} ) {
        # Enforce the "There can be only one default Board" rule ...
        my $dbh = Bugzilla->dbh;
        $dbh->do('UPDATE ' . DB_TABLE . ' SET defaultBoard = 0', undef, undef );
    }  

    my $board = $class->SUPER::create( $params );
    
    $dbh->do( 'DELETE FROM pambaan_boards_group_map WHERE board_id = ?', undef, $board->id() );
    
    $dbh->bz_commit_transaction();

    return $board;
}

sub update {
    my $self = shift;
    
    my $dbh = Bugzilla->dbh;
    
    #
    # Reminder for those who are new to the Bugzilla framework:
    # Will start a transaction if none is already active. Else the transaction call counter will just be incremented.
    # 
    $dbh->bz_start_transaction();
    
    my $changes = $self->SUPER::update(@_);

    if (exists $changes->{defaultBoard}) {
        # Enforce the "There can be only one default Board" rule ...
        $dbh->do('UPDATE ' . DB_TABLE . ' SET defaultBoard = 0 WHERE id != ?', undef, $self->id);
    }
    
    #
    # Reminder to those who are new to the Bugzilla framework:
    # Will commit the transaction if i) a transaction is active and ii) transaction counter is one.
    # Else the transaction counter will just be decremented.
    #
    $dbh->bz_commit_transaction();
    
    return $changes;
}


sub get_all {
    my $invocant = shift;
    my $class = ref($invocant) || $invocant;
    
    my $params = shift;
    my $with_lanes = $params->{with_lanes} if ref( $params ) eq 'HASH';
    
    my @boards = $class->SUPER::get_all();
    
    map{ $_->_add_lanes()  } @boards if $with_lanes;
    
    return @boards;
}

sub get_all_accessible {
    my $invocant = shift;
    my $class = ref($invocant) || $invocant;

    my $params = shift;
    my $with_lanes = $params->{with_lanes} if ref( $params ) eq 'HASH';

    my $table = $class->DB_TABLE;
    my $cols  = join(',', $class->_get_db_columns);
    my $order = $class->LIST_ORDER;

    my $sql = <<"EOSQL";
SELECT DISTINCT
       $cols 
  FROM $table AS $table
  LEFT JOIN pambaan_boards_group_map AS b2g ON $table.id = b2g.board_id
 WHERE b2g.group_id IS NULL
EOSQL

    my $grouplist = Bugzilla->user->groups_as_string;
    $sql .= " OR b2g.group_id IN ( $grouplist )" if defined $grouplist;
    
        
    my $dbh = Bugzilla->dbh;
    my $objects = $dbh->selectall_arrayref($sql, {Slice=>{}});
    bless ($_, $class) foreach @$objects;

    my @boards=@{ $objects };
    map{ $_->_add_lanes()  } @boards if $with_lanes;

    return @boards;    
}

sub transientnew {
    my $invocant = shift;
    my $class = ref($invocant) || $invocant;
    my $name = shift;
    
    my $self = { };
    
    bless($self, $class);
    
    # $self->name( $name ) if defined $name; # !!! Don't do this ... will cause validation as method delegates to set( field, value )
    $self->{name} = $name if defined $name;
    return $self;
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
    # my $self = shift; my $name = shift;
    my ($self, $name) = @_;
    $self->set ( 'name', $name ) if defined $name;
    return $self->{name};  
}

sub description {
    my ($self, $description) = @_;
    $self->set( 'description', $description ) if defined $description;
    return $self->{description};  
}
sub defaultBoard {
    my ($self, $defaultBoard) = @_;
    $self->set( 'defaultBoard', $defaultBoard ) if defined $defaultBoard;
    return $self->{defaultBoard};  
}

# For set_all
sub set_name{
    $_[0]->set('name', $_[1]);
}
# For set_all
sub set_description{
    $_[0]->set('description', $_[1]);
}
# For set_all
sub set_defaultBoard{
    $_[0]->set('defaultBoard', $_[1]);
}


sub has_lanes {
    my $self = shift;
    return ( $self->number_of_lanes > 0 );
}

sub number_of_lanes {
    my $self = shift;
    return scalar @{$self->lanes()};
}

sub lanes {
    my $self = shift;
    $self->{lanes} = $self->{lanes} || [];   
    return $self->{lanes};
}



sub has_groups {
    my $self = shift;
    return ( $self->number_of_groups > 0 );
}

sub number_of_groups {
    my $self = shift;
    return scalar @{$self->groups()};
}

sub groups {
    my $self = shift;

    if ( $self->{groups} ) {
        return wantarray ? ( $self->{groups}, $self->{group_ids} ) : $self->{groups};
    }

    # don't need an ORDER BY as new_from_list will rely on $Bugzilla::Group::LIST_ORDER
    my $sql = <<'EOSQL';
SELECT b2g.group_id 
  FROM pambaan_boards_group_map b2g
  JOIN groups g ON ( b2g.group_id = g.id ) 
 WHERE b2g.board_id = ?
EOSQL

    my $dbh = Bugzilla->dbh;
    my $group_ids = $dbh->selectcol_arrayref( $sql, undef, $self->id );
    return [] if $self->{error};
    
    $self->{group_ids} = $group_ids;
    $self->{groups} = Bugzilla::Group->new_from_list($group_ids);
    return wantarray ? ( $self->{groups}, $self->{group_ids} ) : $self->{groups};
}

sub update_groups {
    my ( $self, $delta ) = @_;
    
    my $board_id = $self->id;
    my $newgroups       = $delta->{add};
    my $removegroups    = $delta->{remove};
    
    map( detaint_natural($_), @$newgroups ) if $newgroups;

    my $dbh = Bugzilla->dbh;

    if ( $removegroups ) {   
        map( detaint_natural($_), @$removegroups ) if $removegroups;  
        my $remove_ids = join(", ", @$removegroups );
        $dbh->do( "DELETE FROM pambaan_boards_group_map WHERE board_id = ? AND group_id IN ( $remove_ids )", undef, $board_id );
    }
    
    my $stmt = $dbh->prepare( "INSERT INTO pambaan_boards_group_map( board_id, group_id ) VALUES ( ?, ? ) " );
    foreach my $group_id ( @$newgroups ) {
        $stmt->execute( $board_id, $group_id );
    }
    $stmt->finish;
    
    #
    # a new call to $self->groups must rebuild the list from the database.
    delete $self->{groups};
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
    $name || ThrowUserError('pambaan_board_blank_name');

    if (length($name) > PAMBAAN_MAX_BOARD_SIZE) {
        ThrowUserError('pambaan_board_name_too_long', {'name' => $name, 'namelimit' => PAMBAAN_MAX_BOARD_SIZE});
    }

    my $board = new Bugzilla::Extension::PAMBAAN::Board({name => $name});
   
    if ($board && (!ref $invocant || $board->id != $invocant->id)) {
        # Check for exact case sensitive match:
        if ($board->name eq $name) {
            ThrowUserError('pambaan_board_name_already_in_use', {'board'            => $board->name});
        }
        else {
            ThrowUserError('pamaan_board_name_diff_in_case',    {'board'            => $name,
                                                                 'existing_board'   => $board->name});
        }
    }
    return $name;
}

sub _check_description {
    my ($invocant, $description) = @_;
    $description = trim($description);
    $description || ThrowUserError('pambaan_board_blank_description');

    return $description;
}

#
#                                                                         ______________________________ 
#                                                                        /                              \
# ---------------------------------------------------------------------- | Modifiers                     |
#                                                                        \______________________________/
#


sub _add_lanes {
    my $self = shift;
    my $lanes = Bugzilla::Extension::PAMBAAN::Lane->get_all_for_board( $self );

    $self->add_lane( $_ ) foreach @$lanes;
}

sub add_lane {
    my($self, $arg ) = @_;
    
    my $lanes = $self->lanes();

    if ( defined $arg ) { 
        if ( blessed( $arg ) && $arg->isa( 'Bugzilla::Extension::PAMBAAN::Lane' ) ) {
            my $lane = $arg;
            if ( !defined $lane->sortkey() ) {
                my $sortkey = $self->number_of_lanes(); 
                $sortkey++;
                $sortkey*=10;
                $lane->sortkey($sortkey);
            };
            
            push @$lanes, $lane;
        } else {
            my $name = $arg;
            my $sortkey = $self->number_of_lanes(); 
            $sortkey++;
            $sortkey*=10;
            
            my $lane = new Bugzilla::Extension::PAMBAAN::Lane( { name=>"$name", board_id=>$self->id(), sortkey=>$sortkey, description => "Lane named $name", color=>"gray" } );
            push @$lanes, $lane if $lane;
        }
    }
    
    return $lanes;
}



sub _add_group {
    my ($self, $arg ) = @_;
    
    my $groups = $self->groups();
    
    my $group;
    if ( $arg ) {
        SWITCH: {
        
            ref( $arg ) && ref( $arg ) eq 'Bugzilla::Group' && do {
                ### warn __PACKAGE__, "::add_groups. Got Bugzilla::Group ", $arg->{id}, " ", $arg->{name}, "\n";
                my $group = $arg;
                last SWITCH;
            };
            detaint_natural( $arg ) && do {
                ### warn __PACKAGE__, "::add_groups. Got some id, maybee valid group id ", $arg, "\n";
                my $group = new Bugzilla::Group( $arg );
                last SWITCH;
            };
        }
        push @$groups, $group if $group;
    }
}


1;

__END__

=head1 NAME

Bugzilla::Extension::PAMBAAN::Board

Based on L<Bugzilla::Object>.

=head1 DESCRIPTION


=head1 SYNOPSIS

=head2 Transient Instances

 
    use Bugzilla::Extension::PAMBAAN::Lane;
    
    sub someMethod{
        my $adminuser = new Bugzialla::User( "admin@mydomain.tld" );
        my $lane = Bugzilla::Extension::PAMBAAN::Lane->transientnew( "First Board" );
        );
    }


=head2 Persistent Instances

    use Bugzilla::Extension::PAMBAAN::Board;
    
    sub someMethod{
        my $adminuser = new Bugzialla::User( "admin@mydomain.tld" );
        my $board = new Bugzilla::Extension::PAMBAAN::Board( "First Board");
        
        my $lane1 = Bugzilla::Extension::PAMBAAN::Lane->create( 
            {
                name                    =>  "First Board", 
                description             =>  "My first Board", 
                defaultBoard            =>  0
            }
        );
    }


=head1 FIELDS


=head1 CLASS METHODS

=head2 INSTANCE CREATION

As you can see from the L</SYNOPSIS> and taking into account that Bugzilla::Extension::PAMBAAN::Board is a L<Bugzilla::Object>, there
are three methods for instance creation.

=over

=item 
C<new> and C<create>

as inherited from L<Bugzilla::Object/new> and L<Bugzilla::Object/create>

=item
C<transientnew>

defined here

=back

Where C<new> can also traverse the dependency graph (C<< { ... with_lanes=>1 } >>) and gather the C<Bugzilla::Extension::PAMBAAN::Lane>s
associated with the board, C<create> and C<transientnew> won't do this for obvious reason.


=head1 METHODS

=head2 PUBLIC Methods

=head2 PRIVATE Methods

=head3 _add_lanes

Add all the board's lanes from the database to this instances list of lanes

    $board->_add_lanes();

=cut
