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


sub _standard_where {
    my ($self) = @_;
    my @where = ( 'bugs.creation_ts IS NOT NULL' );
    
    my $user = $self->_user;
    if ($user->id) {
        my $userid = $user->id;
        my $security_term = "( bugs.assigned_to = $userid )";

        push(@where, $security_term);
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
    
    return @joins;
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

For the Pambaan board we only want to have the bugs which are assigned to the current user
or she/he can access due to group membership. We do not want to have the bugs where the current user is the 
reporter or member of the cc. We could have tweaked C<_standard_where> only but by adapting C<_standard_joins>
we get rid of one JOIN with the C<cc> table.

The C<_standard_where> also includes the QA contact if Bugzilla is configured to C<useqacontact>. The
current implementation also ommits the QA contact.

=cut
