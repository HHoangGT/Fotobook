package com.fotobook.recommendation.flink.functions;

import com.fotobook.recommendation.flink.models.PopularPhoto;
import org.apache.flink.streaming.api.functions.windowing.ProcessAllWindowFunction;
import org.apache.flink.streaming.api.windowing.windows.TimeWindow;
import org.apache.flink.util.Collector;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

/**
 * Ranks photos by popularity score
 */
public class PopularPhotoRankingProcess extends ProcessAllWindowFunction<
    PopularPhoto,
    PopularPhoto,
    TimeWindow> {

    @Override
    public void process(Context context,
                       Iterable<PopularPhoto> elements,
                       Collector<PopularPhoto> out) throws Exception {
        
        List<PopularPhoto> photos = new ArrayList<>();
        for (PopularPhoto photo : elements) {
            photos.add(photo);
        }

        // Sort by score descending
        photos.sort(Comparator.comparing(PopularPhoto::getScore).reversed());

        // Assign ranks and emit
        long rank = 1;
        for (PopularPhoto photo : photos) {
            photo.setRank(rank++);
            photo.setWindowStart(context.window().getStart());
            photo.setWindowEnd(context.window().getEnd());
            out.collect(photo);
        }
    }
}