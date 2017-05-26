# hedis-cluster

I'm uncertain if anything more will come of this than some toying around.

After discovering that redis has a cluster mode and that hedis doesn't support it out of the box
I got the idea to try my luck with implementing a wrapper that uses hedis along with some cluster specific logic,
which should mainly consist of directing commands to the nodes that they should end up at.

If all goes right (but does it ever?) this could become a working library.

If you have any ideas about this project, please feel free to do something about it or leave me some feedback.
