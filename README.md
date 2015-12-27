# PAMBAAN
SimpleKanban - Bugzilla Extension for a Simple Kanban Board

Current Version

Current Version is v.0.6.2. Older versions will not be available.
What's new with v.0.6.2?

    Selecting an other board in the board view automatically triggers loading the board. You don't have to press the refresh button.
    This might be an issue on large bugzilla databases as the queries then may take some time to run.
    Fixed a layout problem when displaying a large number of bugs: Assigned a min-height to #header and #pambaanboard_header.
    Adding <meta name="viewport" ...> to the page header when displaying the SimpleKanban board. So it will display somehow better on mobile Browsers.
    The SimpleKanban Board and the cards now have a background-color each.

What's new with v0.6.1?

    Fixed a hidden bug in the Lane editing page with “Work in Progress” fields.
    You can now define “Personal” boards – these will show only those bugs where the current user is the asignee.

The version increment does not value that there has been an increase in functionality
What's new with v0.6.0?

    You can now configure on board level how to handle blocked bugs.
        Display them
        Treat them as "Read Only"
        Hide them

"Read only" - still a bad name. Still has to be reworked.
What's new with v0.5.0?

    You can now configure the card's content per lane: Turn on/off
        Product
        Importance
        Status
        Asignee
        Timetracking

What's new with v0.4.n?

    Group access control. Assign a board to one or many groups. These boards will be availabe to users in this group, only.
    v0.4.1 tweaks the named query/shared search: The result will not include bugs for which the user is the reporter or on the cc list.
    v0.4.2 adds timetracking information to the card.
    v0.4.2 also factors out the creation of the card to pambaan/card.html.tmpl so that users can adapt the card layout by writing a custom/pambaan/card.html.tmpl
    and it fixes a bug introduced with v0.4.1. The tweaked Search discarded the bugs to which the user has access via group control.

What's new with v0.3?

    The extension now displays itself as SimpleKanban ...
    ... but one can configure this in the variables-end.none.tmpl
    You can now define two thresholds per Lane
        A Warning Threshold indicating the number of bugs wherefrom to warn that the lane will soon be “full”
        An Overload Threshold indicating the number of bugs wherefrom the lane will be considered “full” 
    The board will not enforce the Overload Threshold, though, as the lanes are not populated explicitely with bugs but by a named search.
    You can size the width of the lanes. Before all lanes had the same width. Now you can define that a lane is two or three times wide compared to normal.

Upcoming
No ideas yet ...
Installation

    Download the archive
    Unpack the archive
    Move the PAMBAAN folder to your Bugzilla's extension directory
    Run checksetup.pl. If something goes wrong you'll have to anlyse yourself 1)
    This will
        Create the database tables
        Insert a new group named pambaan
        Create a new board named «Default» with 4 lanes ...
        ... and create 4 saved searches which are assigned to the lanes 2)

1) I already experienced issues with my code when installing on a Bugzilla running under Perl 5.10. I am developing with 5.18

2) The extension makes the assumption that the profile with id 1 (one) exists which will be the owner of the queries. If for some reason this id does not exist (any more), the searches will not be created.
Configuration

Before you can use the SimpleKanban board, you have to do some configuration. Assuming that you will start with the «Default» board:

    Assign all users who should work with SimpleKanban to the newly created group pambaan
    If for some reason 2) there are no named queries / shared searches assigned to the board's lanes:
        Create shared named queries - for the «Default» board you need 4 queries
        Go to the Administration page and there to «SimpleKanban boards»
        Assign these named queries to eacho of the lanes (Choose board → follow «Edit lanes» link → Choose each lane)

Integration with Bugzilla

As one can see already from the configuration instructions, the SimpleKanbaan extension relies on several of Bugzilla's mechanisms

    It uses group memberships to control which users have access to the SimpleKanban boards. Only users in group pambaan will get the menu entry in the header.
    It of course uses group memberships to control which users can add, delete or modify boards and lanes, resp.
    It uses named queries / saved searches for populating lanes with bugs. These queries have to be shared with the pambaan group.

Using named queries / saved searches

The lanes of a SimpleKanban board are populated with bugs by a named query / saved search. So you have to make sure that the named queries / saved searches

    return disjunctive sets of bugs so that a bug would not appear in more than one lane of the board
    the queries represent the Kanban workflow from left to right so that a bug would not jump for- and backwards between lanes against the workflow

The «Default» board installed by the extension meets this criteria as each lane is populated according to the bug's status lifecycle:
UNCONFIRMED → CONFIRMED → IN_PORGRESS → RESOLVED

IMHO this approach fits very well into Bugzilla's UX. The whining module, for example, also uses saved searches for determining the bugs to whine on. The main intention of this Kanban implementation is that developers can easily get an idea of what still has to be done on the one hand and what they are currently working on on the other hand.

Maybe for a use case “resource planning” directly assingning bugs to lanes would be a better approach. So a manager could use the board for planning her/his team members for the next sprint and easily play with scenarios by dragging bugs between lanes.

attention With version v.0.4.1 the SimpleKanban board internally uses a modified search – so there may be differences between the number of bugs you get when you execute your saved search and when the search is executed for the SimpleKanban board:
Bugzilla's standard search mechanism also includes those bugs for which the user is the reporter or on the cc list, or (depending on the settings for usequacontact) for which she/he is the qa contact3) for the bug. In the context of a Kanban board this makes no sense.

3) I am not sure about excluding the QA. Maybe this should be a property of the board or a specific lane if it should bugs for which the user is the QA contact ...

#) Explicitly assigning bugs to lanes would mean to extend Bugzilla::Bug and intercepting a bug's create and update lifecycle by implementing several hook methods – maybe not a good idea for one's first extension.
Integration with Bugzilla's User Interface

The page displaying a SimpleKanban board interferes with Bugzilla pages such that it alters the <body> and <div id="bugzilla-body"> into a CSS3 Flex Container (Maybe you want to read A Complete Guide to Flexbox or watch CSS Fleybox Essentials on Youtube DevTips channel). It does so by adding the override.css stylesheet to the page's header in the correponding processing hook. This works with Bugzilla 4.x and also seems to work with with Bugzilla 5.0.x without any issues.

According tho the Bugzilla Roadmap the team wants to get away from table based to div based layouts. The styling of the SimpleKanban board page will have to be checked for compatibility then.
Browser compatibility

The SimpleKanban Board uses CSS§ Flex Container layout for displaying the lanes. This has been coarsly+) tested with

    FF43 (under OS X, Windows)
    FF42 (under Linux Mint, OS X)
    FF41 (under OSX)
    FF35 (under Windows)
    Chromium 47.x (under Linux Mint)
    Chrome 47.x (under OS X, Windows)
    Safari 9.x (under OS X and iOS)++)

+) Coarse test means that I checked that the SimpleKanban Board displays the Default board with 4 lanes.

++) Along with the <meta name="viewport" ...> tag the SimpleKanban Board displays somehow nice on at least the iPad

You would need some CSS experience to fix any display issues for your browser version.
