KICKASS ?= java -jar $$HOME/c64/kickass/KickAss.jar
SPIN ?= $$HOME/c64/spindle-3.1/src/spin

FFMPEG ?= ffmpeg
VOICE_SAMPLES := $(wildcard data/*.c1)
INFERENCE_SOURCES = src/inference.asm src/inference_macros.asm src/inference_macros_single.asm src/inference_macros_pair.asm

VIDEO_SEGMENTS := out_disk1.avi out_disk2.avi out_disk3.avi out_disk4.avi out_disk5.avi out_disk6.avi

DISK_IMAGES := dist/mnist64.d64 dist/mnist64b.d64 dist/mnist64c.d64 dist/mnist64d.d64 dist/mnist64e.d64 dist/mnist64f.d64
COMMON_SOURCES := src/generated_model_header.asm src/macros.asm

all: $(DISK_IMAGES)

clean:
	rm -f audio.prg demo.prg inference.prg lookup.prg model.prg src/*.sym *.vs

clean2: clean
	rm -rf dist

%.prg src/%.sym: src/%.asm Makefile
	$(KICKASS) src/$*.asm -o $*.prg $(if $(filter demo,$*),-vicesymbols)

demo.prg src/demo.sym: src/demo_layout.asm src/scroller.asm src/ui.asm src/drawing.asm src/inc_irq.asm $(COMMON_SOURCES) src/build_defaults.asm inference.prg src/inference.sym

audio.prg src/audio.sym: src/demo_layout.asm $(VOICE_SAMPLES)

inference.prg src/inference.sym: $(INFERENCE_SOURCES) $(COMMON_SOURCES) src/demo_layout.asm src/build_defaults.asm src/model_symbols.asm lookup.prg src/lookup.sym audio.prg src/audio.sym

model.prg src/model.sym: $(COMMON_SOURCES) src/generated_model.asm src/generated_early_head.asm

lookup.prg src/lookup.sym: src/lookup_tables.asm src/demo_layout.asm $(COMMON_SOURCES)

# Each disk is independently rebuildable. Track every payload named by its
# Spindle script so image, label, and disk-marker changes cannot go stale.
script_inputs = $(sort $(shell awk 'NF {print $$1}' $(1)))

dist/mnist64.d64: data/script demo.prg inference.prg model.prg lookup.prg audio.prg data/screen.prg data/scheisse.prg data/mnist_test_2bit.labels.bin data/mnist_test_2bit.bin
	mkdir -p dist
	"$(SPIN)" -v -q -a data/mnist64_dirart.prg -t "MNIST64 1/6" -m EF8381 -n EF8382 -o dist/mnist64.d64 data/script
	"$(SPIN)" -v -F -q -a data/mnist64_dirart.prg -t "MNIST64 2/6" -m EF8382 -n EF8383 -o dist/mnist64b.d64 data/script2
	"$(SPIN)" -v -F -q -a data/mnist64_dirart.prg -t "MNIST64 3/6" -m EF8383 -n EF8384 -o dist/mnist64c.d64 data/script3
	"$(SPIN)" -v -F -q -a data/mnist64_dirart.prg -t "MNIST64 4/6" -m EF8384 -n EF8385 -o dist/mnist64d.d64 data/script4
	"$(SPIN)" -v -F -q -a data/mnist64_dirart.prg -t "MNIST64 5/6" -m EF8385 -n EF8386 -o dist/mnist64e.d64 data/script5
	"$(SPIN)" -v -q -a data/mnist64_dirart.prg -t "MNIST64 6/6" -m EF8386 -o dist/mnist64f.d64 data/script6

out_concat.avi: $(VIDEO_SEGMENTS)
	printf "file '%s'\n" $(VIDEO_SEGMENTS) > concat_list.txt
	$(FFMPEG) -y -f concat -safe 0 -i concat_list.txt -c copy $@

out_50hz.mp4: out.avi
	$(FFMPEG) -y -i $< -t 10800 \
	  -vf "scale=iw*5:ih*5:flags=neighbor,crop=1800:1200,setpts=1.00249084*PTS" \
	  -af "asetrate=48000*0.99751521,aresample=48000" \
	  -r 50 -fps_mode cfr \
	  -c:v libx264 -crf 16 -pix_fmt yuv420p \
	  -c:a aac -b:a 128k -ar 48000 \
	  $@

out_60hz.mp4: out.avi
	$(FFMPEG) -y -i $< -t 10800 \
	  -vf "scale=iw*5:ih*5:flags=neighbor,crop=1800:1200" \
	  -r 60 -fps_mode cfr \
	  -c:v libx264 -crf 16 -pix_fmt yuv420p \
	  -c:a aac -b:a 128k -ar 48000 \
	  $@

video: out_60hz.mp4

clean-video:
	rm -f concat_list.txt out_concat.avi out_50hz.mp4

.PHONY: all clean clean2 video clean-video
