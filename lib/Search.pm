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


package Bugzilla::Extension::PAMBAAN::Search;
use strict;
use base qw(Bugzilla::Search Exporter);
our @EXPORT = qw();  
our $version="0.6.2";

use Data::Dumper;


sub _standard_where {
    my ($self) = @_;
    my @where = ( 'bugs.creation_ts IS NOT NULL' );
    
    my $security_term = "security_map.group_id IS NULL";
    my $user = $self->_user;
    if ($user->id) {
        my $userid = $user->id;
        $security_term .= " OR bugs.assigned_to = $userid";
        
        $security_term = " ( $security_term ) ";

        push(@where, $security_term);

        push(@where, "( bugs.assigned_to = $userid )") if $self->{personal};
    }
    


    return @where;
}

sub _standard_joins {
    my ($self) = @_;
    my $user = $self->_user;
    my @joins;

    my $security_join = {
        table => 'bug_group_map',
        as    => 'security_map',
    };
    push(@joins, $security_join);

    if ($user->id) {
        $security_join->{extra} =
            ["NOT (" . $user->groups_in_sql('security_map.group_id') . ")"];
    }
    
    my %fields = map{ $_ => 1 } @{$self->{fields}};

    if ( $fields{dependantslist} ) {
        my $dependencies_join = {
            table => '(SELECT blocked, group_concat(dependson) AS dependantslist FROM dependencies GROUP BY blocked )',
            as    => 'dependency_map',
            from  => 'bug_id',
            to    => 'blocked',
        };
        
        push(@joins, $dependencies_join);
    }
    
    if ( $fields{blockinglist} ) {
        my $blockers_join = {
            table => '(SELECT dependson, group_concat(blocked) AS blockinglist FROM dependencies GROUP BY dependson )',
            as    => 'blocking_map',
            from  => 'bug_id',
            to    => 'dependson',
        };
        
        push(@joins, $blockers_join);
    }
    
    return @joins;
}

sub COLUMNS {
    my $self = shift;
    my $columns = $self->SUPER::COLUMNS();
    
    $columns->{dependantslist} = { name => 'dependency_map.dependantslist', title => 'Dependants List' };
    $columns->{blockinglist}   = { name => 'blocking_map.blockinglist',     title => 'Blocking List' };
    $columns->{blocked}        = { name => 'CASE WHEN blockinglist IS NULL THEN 0 ELSE 1 END', title => 'Blocked' };
        
    return $columns;
}


1;


__END__

=head1 NAME

Bugzilla::Extension::PAMBAAN::PambaanSearch

Based on L<Bugzilla::Search>.

=head1 DESCRIPTION

Subclass to tweak the methods

=over

=item
C<_standard_where> 

=item
C<_standard_joins>

=back

methods of L<Bugzilla::Search>.

=head1 METHODS

=head2 PRIVAT METHODS

=head3 _standard_joins

Modified C<_standard_joins> for Pambaan. 

We do not want to have the bugs for which the current user is the reporter, QA contact
or on the bug's CC list. These bugs do not contribute to the workload. So do not C<JOIN> with the C<cc> table.

If the L<Bugzilla::Extension::PAMBAAN::Board> is configured to factor dependencies we need to know for each bug if

=over

=item
the bug depends on one or several other bugs

=item
the bug blocks another bug

=back

So C<JOIN> with the dependencies table for getting the list of dependent bugs and C<JOIN> with the
dependencides table for getting the list of blocked bugs.

=head3 _standard_where

We do not want to have the bugs for which the current user is the reporter, QA contact
or on the bug's CC list. So do not check for reporter an cc.

=cut
