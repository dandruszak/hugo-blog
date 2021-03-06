---
title: "Porting IceCI to ARM"
date: 2020-03-26
draft: false 
hero: "./images/post/2020-03/arm1.jpeg"
excerpt: A story of me being silly
authors:
  - Jakub Czaplinski
tags:
  - Docker
  - Kubernetes
  - Raspberry Pi
  - Raspbian
  - Devops
---

## Disclaimer

This is not a tutorial. It’s a story with a sort of a happy ending and a lesson to learn. When we will finish testing of [IceCI](https://iceci.io) on various ARM based machines and tidy up after the “hack to test” solution in the next release we will prepare a separate article with a tutorial and a lot of technical facts regarding the preparation of cross architecture products. But for now — have fun and laugh a bit :)

## Mindset

Being a dev that recently mostly writes in Golang and Python I’m kind of used to cloning the sources on a machine and running them. Both Golang and Python have great portability and developers are able to get all the necessary tools to build and run their programs very easily.

Same goes for Docker. I’m so used to being able to do `docker pull` and run things that I need, that I often forget which system version I'm actually running on my host - it is irrelevant because my image is - for example - `debian:10.1`.

{{<post_image src="./images/post/2020-03/arm2.jpeg" caption="The so-called K3s cluster">}}

Those combined experiences gave me an idea — a silly one — that we can port IceCI to ARM architecture and run it on one of my Raspberry Pis in just a few commands. I already had a node k3s cluster running for tests, so what can go wrong?

Seriously I will end up with this one tatooed someday…

## Wednesday ~10PM

Wednesday, 10PM after 8h of work and couple of chores — the perfect mindset for engineering!

To even start I needed to compile the application to ARM architecture. The whole backend is in Golang so cross compilation is built in by default. I just needed to set the proper GOARCH environment variable and I’m good to go. Quick googling with DuckDuckGo — the Raspberry Pi docs say that version 4 is 64bit ARMv8. Perfect!

```shell script
export GOARCH=arm64
make build
```

And now I’m thinking to myself — ok, this is different architecture, I just need to put it into a different docker image.

```shell script
export IMG_VER=alpha4-arm
make docker-publish-iceci
```

I have copied and edited the `all_in_one.yaml` from the [IceCI repository](https://github.com/iceci/) and changed the tag to `alpha4-arm`. Need to `kubectl apply` it and I'm good to go!

I’m staring at the screen as the images are pulled and the containers are created… a sudden sad realization hits me when I see

```shell script
standard_init_linux.go:211: exec user process caused "exec format error"
```

Well, what about the other things in the container, like nginx? Those should be built for ARM too…

I never thought too much about how images are made for different architectures, but I quickly looked at Docker Hub and gathered some information. Ok — turns out I can use the `arm64v8/debian:10` image to build the application for ARM. I copied the docker files with the -arm suffix and changed the `FROM` clause to `FROM arm64v8/debian:10`

Another image build run. I run `kubectl delete pod --all` to delete all the existing pods and wait for the new image versions to download and start.

I’m staring at the screen and suddenly I see…

```shell script
standard_init_linux.go:211: exec user process caused "exec format error"
```

What?! I’m checking `kubectl describe` and I see that yes, the new images were pulled.

Investigation time! I’m logging into the Raspberry with ssh to do a check that I should have done in the first place.

```shell script
upgrade@rpi4:~ $ uname -a
Linux rpi4 4.19.97-v7l+ #1294 SMP Thu Jan 30 13:21:14 GMT 2020 armv7l GNU/Linux
```

\<insert random facepalm gif here\>

Ok, a couple of deep breaths — let’s find out what I did wrong. After a quick search it seems, quite reasonably, that Raspbian only supports the 32 bit armv7 build as support the 64 bit one was too much work for them. Fair enough, that’s understandable — they are still doing a massively cool thing with Raspberry Pi and Raspbian.

So now I’m back to square one. Set the `GOARCH=arm`, change the `FROM arm64v8/debian:10` to `FROM arm32v7/debian:1` and build... build... build.. push... Then of course, as I'm impatient `kubectl delete pod --all`

and….

SUCCESS!

I see all pods coming up, so I’m checking which port Traefik is listening on and try accessing the UI. Time to add one of our test pipelines and run it. After adding the repository I’m waiting for the CI to do the first repository event scan, so I can push some changes and trigger a pipeline build. After alt-tabbing to a terminal running k9s with a pod list the smile disappears from my face again. For a second time this evening I have this realization — before I even looked at the logs I knew… I knew that we were using the `iceci/utils` image which contains Git and other utils to fetch changes from the repo and analize them. And well.. I did not rebuild them for ARM, as they are in a separate repo. So I create branch on my fork of the `iceci/docker-images` repo and change the `FROM` in docker file to `FROM arm32v7/debian:10`, run docker build and... another facepalm...

This time, as I was getting a bit tired, the thought came in slower and more gently. The previous images had just `ADD`, `CMD` and `EXPOSE` operations in docker file. This one has `RUN`, and I couldn't run ARM based images on my machine for the same reason that I could not run my arm64 images on Raspberry. And another thing - I will need to do some changes in the code. We have been preparing to have all of the image version passed as environment variables, however not all of them were passed to the builder - the component preparing specs for pods.

## Thursday — ~1AM

The builder Raspberry Pi installation has finished.

{{<post_image src="./images/post/2020-03/arm3.jpeg" caption="Another Raspberry Pi to build the images">}}

I made all the necessary changes to the application. I built and pushed both the app and the `iceci/utils` images.

Kill all pods…

Run a pipeline and…. finally!

‘Hello world’ worked.

I have setup all secrets and added an example repository with a sample application (which has been created for the purposes of IceCI tutorials). After adding I waited for IceCI to start scanning for Git events, pushed a commit with empty line and waited… again…

And another fail…

Well the *kaniko* image that we use to build Docker images (as of writing this article we had 0.16 and 0.19 was out) does not support ARM builds.

After short research and a quick test — I found out that we could use *buildkit* for ARM base pipelines. *Buildkit* apparently is a little bit less secure so I figured it would be best if we have support for both and continue to use kaniko on x86_64 and use *buildkit* only on ARM.

At this point it’s close to 2AM and I’m too tired. I left Ewa and Dominik (my friends, also co-creators of IceCI) some messages with a write-up of the story so far — a bit like what you just read, just with a little bit more swearing. I also asked Dominik to copy/paste the code of our current controller and just change the image building tool from *kaniko* to *buildkit*. The plan is that he will do the sin of copy/pasting and adjusting the code, and I’ll pick up and finish the ARM patchwork tomorrow… today evening.

## Thursday ~10PM

Another night of hacking before me. Little bit more sleep deprived and a little bit less optimistic. As an afterthought of yesterday I have a feeling that something will explode in the application. A feeling that became a prophecy.

So I have merged Dominik’s changes to my branch. Added if/else statements, as an experienced software enigneer with knowledge of good practices, will do. Looked at the controllers with 99% of the codebase copied over and closed my eyes.

In my mind, I kept saying to myself “It’s all right, we will refactor this after release”, “Everything will be all right”, “This bad code will be gone soon”.

I have build the code and images and pushed everything. Killed all the pods, new ones were created. All good. Run the test build. First example passed. Second one failed.

I knew it won’t be all roses and rainbows.

After quick debugging session — thank the kubeclient that I can run operator locally and point it to the RPI cluster — and I found that a missing environment variable in the *buildkit* pod allowed only for couple of commands to be run in Dockerfile. Small update in the code, build, push, kill all pods (it’s beginning to get repetitive and I’m hearing Bender’s “kill all humans” in my head). And finally all is working.

At this point I know that we have to merge changes, tag everything and make a PR to the docs, but that can be done in the morning. Right now I just need to make a screenshot and paste on slack, do a victory dance (though a low energy and not a convincing one) and go to bed as it is around midnight.

## Friday ~11AM

Documentation updated, everything merged, repositories tagged. Small series of tests yet again. Everything is working. Post on LinkedIn done. Post on twitter done. All super cool, except the fact that I still feel like I need a shower. And I just took one 1 hour ago. After my last commit to the repository with code I actually took two showers, but still felt like I need one.

The more I thought about it the more I saw how many mistakes were made and I decided to write all of this up to share both the story and my thoughts about it.

## The afterthought — lessons learned

Why share all of this and risk building an image of a person who is chaotic or a bit incompetent? I do strongly believe in devops philosophy and the CALMS principles, and in CALMS the S stands for *Sharing*. I think that there are a lot of lessons to learn here and I will share my thoughts, and feel free to share your own.

In both trainer and leader role I always try to encourage people to slow down and think before doing. I talk a lot about “furious activity” and how it can slow down the overall process of development by jumping to conclusions or just randomly changing the code or configuration and immediately testing without taking a second to actually analize properly what is happening. And as you can see, no matter how I’m proud of that approach and how much energy I put into promoting it, I also became the “furious activity” victim. I was so focused on delivering and in my mind it was supposed to be a super quick and easy thing to do, that I was hacking and hacking and hacking… and never hit the breaks and thought — hold on a minute, what am I actually doing? — which I should do after first problem occurred.

I can’t complain that my evil boss or project manager or any other supervisor forced me to do this and pushed me to my limits as I was that person and all of the blame is on me. I really wanted to push this release on Friday, so that I can play around with it, share with friends and work on other articles in the pipeline over the weekend. Instead, for better of for worse, I actually wrote this one. Right now, after having a good night sleep, I have estimated that this could took around 6 hours of development with proper research. One could say that’s roughly the time I actually spent on it during this hackaton and that is true, however now I have evil copy/paste code in our codebase and some crazy if/else statements to refactor. Oh, and of course I have the images on separate tags which makes the life of IceCI users a bit more painful. Now I know how to release it on the same tag, and I have learned how all of this works with the Docker registry v2.2 manifests. So there is still some work ahead of us because I hacked it like that.

Another thing is working tired versus being rested. Lately many people talk about reducing the number of work hours and how it can impact productivity. On the opposite side I think lots of people had a job where overtime was a normal thing because people were pushed too deliver on time, even if the deadline or scope changed after planning. I was a part of so many battles where the engineering team talked with the PO/PM and other decision making groups about pushing things to deadlines and the impact of on team and product. And with all that experience I inflicted same thing on myself. I’m happy that in this case it was a feature / release that mainly I was working on and the deadline hit me, but did not had this much of an impact on others. I felt a little bit stupid nonetheless.

Last but not least — the best way to plan things is to have some kind of research and data to base your plan upon. I did not have any experience with porting things across architectures. I had experience with building Python applications which — by design — had to run on Windows and Linux but never porting things like that. Like I mentioned in the beginning of this article, I based my estimates on a hunch and experience with playing around with Raspberry Pi and using k3s. If I would spend 30 minutes on research I would immediately know what issues I can run into and how to solve them. It’s not that hard, but one has to be in a proper mindset.

In the future I will try to listen to my own advice.
