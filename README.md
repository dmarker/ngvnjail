<!-- put reference links at top
    commit:
      [ng_base][10]
    differential reviews
      [ngctl(8)][20]
      [ng_wormhole(4)][21]
      [ngportal(8)][22]
      [ng_bridge][23]
    man:
      [rc.conf(5)][31]
      [ng_bridge(4)][32]
      [ng_ether(4)][33]
      [ng_eiface(4)][34]
      [jai.conf(5)][35]
      [netgraph(4)][36]
      [loader.conf(5)][37]

  -->
[10]: https://github.com/freebsd/freebsd-src/commit/46f38a6dedb1b474f04b7c2b072825fda5d7bd5a
[20]: https://reviews.freebsd.org/D50241
[21]: https://reviews.freebsd.org/D50244
[22]: https://reviews.freebsd.org/D50245
[23]: https://reviews.freebsd.org/D44615
[31]: https://man.freebsd.org/cgi/man.cgi?query=rc.conf&manpath=FreeBSD+15.0-CURRENT
[32]: https://man.freebsd.org/cgi/man.cgi?query=ng_bridge&manpath=FreeBSD+15.0-CURRENT
[33]: https://man.freebsd.org/cgi/man.cgi?query=ng_ether&manpath=FreeBSD+15.0-CURRENT
[34]: https://man.freebsd.org/cgi/man.cgi?query=ng_eiface&manpath=FreeBSD+15.0-CURRENT
[35]: https://man.freebsd.org/cgi/man.cgi?query=jail.conf&manpath=FreeBSD+15.0-CURRENT
[36]: https://man.freebsd.org/cgi/man.cgi?query=netgraph&sektion=4&manpath=FreeBSD+15.0-CURRENT
[37]: https://man.freebsd.org/cgi/man.cgi?query=loader.conf&manpath=FreeBSD+15.0-CURRENT

# ngvnjail

This is literally just a script I drop into `/usr/local/etc/rc.d` for
[rc.conf(5)][31]. This allows me to configure a couple [ng_bridge(4)][32] and
add my network interface (as [ng_ether(4)][33]) and [ng_eiface(4)][34] to the
bridges at startup.

Using this along with the following reviews (most not in FreeBSD):
* changes to [ng_bridge][23] to allow `link` and `uplink` without numbers.
* changes to [ngctl(8)][20] to add `-j` option.
* a new [netgraph(4)][36] node [ng_wormhole(4)][21].
* a new utility [ngportal(8)][22] to more easily manipulate [ng_wormhole(4)][21].

I also backport all of that and one additional patch to run with FreeBSD14:
* fix for [ng_base][10]

That last fix was required because of my `link` change for [ng_bridge(4)][32].

I mean you can still use this without those for setting things up on your system,
but for the jails configuration and usage you need them all.

Speaking of config...

# loader.conf

For [ng_ether(4)][33] to attach to their interfaces and play with [netgraph(4)][36] you
need to add these to [loader.conf(5)][37]:
```
netgraph_load="YES"
ng_ether_load="YES"
ng_bridge_load="YES"
ng_eiface_load="YES"
ng_wormhole_load="YES"
```

Technically its just the [ng_ether(4)][33] that you need in here but don't forget that
[ngctl(8)][20], even with my changes, can't load kernel modules in a jail! So its probably
best to load what you plan to use.

# Using with rc.conf and jail.conf

Using the `ngvnjail` script you minimaly need somegthing like this in your rc.conf:
```
ngvnjail_enable="YES"
ngbridge_normal="br0 br1"
ngether_re0="br0 ETH"

# Make a separate lan0 with its own ng_eiface. This is base systems main
# network interface.
ngeiface_lan0="br0 1E:F3:8E:FE:AE:AF"

# Our private link to jails.
ngeiface_jail0="br1"

# configure ifconfig_lan0="..." and ifconfig_jail0="..." as normal.
```

Here is what you can have in jail.conf to create a `lan0` and `jail0` interface
for any jail that may want those. If you don't like using the same names
you can change to `lan0$name` and `jail0$name`.
Since wormholes disappear when either end is shutdown (like when a jail is
shut down) you don't need to name them but I do so you can tell at a glance
any particular wormhole's purpose.
```
# This creates an ng_eiface(4) named "lan0" in the jail "$name". The network
# interface is changed to "lan0" as well. Finally this ng_eiface(4) in the
# jail is connected to "br0" on the system with ngportal (that sets up an
# ng_wormhole(4) for the connection.
$lanif="echo -e \"mkpeer eiface e ether\nname .:e lan0\" | ngctl -j $name -f -
ifn=`ngctl -j $name msg lan0: getifname | sed '1d' | cut -d\\\" -f2`
ifconfig -j $name \$ifn name lan0
ngportal :br0$name:br0:link $name:lan0system:lan0:ether";

# same but for a private network on br1
$jailif="echo -e \"mkpeer eiface e ether\nname .:e jail0\" | ngctl -j $name -f -
ifn=`ngctl -j $name msg jail0: getifname | sed '1d' | cut -d \\\" -f2`
ifconfig -j $name \$ifn name jail0
ngportal :br1$name:br1:link $name:jail0system:jail0:ether";
```

Now for each jail you minimally need something similar to:
```
jailname {
  vnet;
  exec.created += "$lanif";
  # you don't want to just use the default on something connected to an
  # ng_bridge(4) connected to ng_ether(4). So set mac different for
  # each jail's "lan0".
  exec.created += "ngctl -j $name msg lan0: set 00:15:5d:01:11:31";
  exec.created += "$jailif";
  exec.start = "/bin/sh /etc/rc";
  exec.stop = "/bin/sh /etc/rc.shutdown jail";
}
```

That is it. You create the [ng_eiface(4)][34] in the jail after the jail is created
but before its started. Because it was created in the jail, the [ng_eiface(4)][34] and
ng_wormhole(4) connected to it go away when the jail does. And when the side of
the wormhole in the jail shuts down, it shuts down the side on the system.

With just three lines you add access to your physical network and a private jail
network. Very template friendly.

I do like using the same name for interfaces in jails so they can all share
a similar configuration for networking but that's just my preference.

ng_wormhole(4) are also friendly to disconnect/reconnect of their event horizon
once "opened". So you can disconnect and insert an ng_pipe(4) for test or you can
add an ng_vlan(4), ng_bpf(4) or whatever you want or need. You can do it in the
jail too, but remember ngctl(8), even modified, doesn't load kernel modules when
given `[-j jail]`, it will correctly tell you its not permitted for jail to load
a kernel module. So you do need to do that first.
