
Perl script to sync individual projects to another Redmine instance.

Status

My current goal is to synchronize one isolated project, which only has
Wiki pages and attachments, from one instance to another.  In the end,
this project shall only be used on the destination instance.  This is
more complicated that initially assumed but still leaves out the rather
hairy problem of migrating issues or even issue numbers and whatever
embedded in Wiki text.

Right now, synchronizing stuff that are related to users work.

The next step is to attack the Wiki.

Why Perl?  I'm not fluent enough in Ruby to even consider it as the
tool of choice for this problem.  The script directly talks with
the MySQL databases of the Redmine instances, it basically ignores
the API.


