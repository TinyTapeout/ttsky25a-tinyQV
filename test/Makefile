.PHONY: all

%-results.xml:
	make -f test_$*.mk clean
	make -f test_$*.mk
	mv results.xml $@

peri-%.xml:
	make -f test_basic.mk clean
	MODULE=user_peripherals.$* make -f test_basic.mk
	mv results.xml $@

all: clean basic-results.xml peri-byte_example.xml peri-edge_counter.xml peri-full_example.xml prog-results.xml peri-matt_encoder.test.xml peri-ledstrip.test.xml peri-impostor_ws2812b.test.xml
	cat *results.xml peri-*.xml > results.xml

clean:
	rm *results.xml peri-*.xml || true
