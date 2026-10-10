package com.tvmaestro.companion;

import android.os.Bundle;
import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        registerPlugin(CompanionPlugin.class);
        super.onCreate(savedInstanceState);
    }
}
