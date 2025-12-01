package com.fotobook.recommendation.flink.functions;

import com.fotobook.recommendation.flink.models.PhotoInteraction;
import com.fotobook.recommendation.flink.models.PhotoCooccurrence;
import org.apache.flink.streaming.api.functions.windowing.ProcessWindowFunction;
import org.apache.flink.streaming.api.windowing.windows.TimeWindow;
import org.apache.flink.util.Collector;

import java.util.*;

/**
 * Processes photo interactions to calculate co-occurrence matrix
 * Photos that are interacted by the same user are co-occurring
 */
public class PhotoCooccurrenceProcessor extends ProcessWindowFunction<
    PhotoInteraction,
    PhotoCooccurrence,
    Long,
    TimeWindow> {

    @Override
    public void process(Long userId,
                       Context context,
                       Iterable<PhotoInteraction> elements,
                       Collector<PhotoCooccurrence> out) throws Exception {
        
        // Collect all photos interacted by this user in the window
        Set<Long> photoIds = new HashSet<>();
        for (PhotoInteraction interaction : elements) {
            photoIds.add(interaction.getPhotoId());
        }

        // Generate co-occurrence pairs
        List<Long> photoList = new ArrayList<>(photoIds);
        for (int i = 0; i < photoList.size(); i++) {
            for (int j = i + 1; j < photoList.size(); j++) {
                Long photo1Id = photoList.get(i);
                Long photo2Id = photoList.get(j);
                
                // Emit both directions (symmetric matrix)
                PhotoCooccurrence cooccurrence = new PhotoCooccurrence(
                    photo1Id, photo2Id, 1L
                );
                cooccurrence.setWindowStart(context.window().getStart());
                cooccurrence.setWindowEnd(context.window().getEnd());
                out.collect(cooccurrence);
            }
        }
    }
}